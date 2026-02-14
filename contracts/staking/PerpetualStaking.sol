// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title PerpetualStaking
/// @notice TODO: Add description of what this contract does
/// @custom:security-contact tech@brickken.com
contract PerpetualStaking is OwnableUpgradeable {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    /*
        Solvency model (simple interest with piecewise yields):

        For user i with principal d_i and deposit time t0_i, the current value at time t is:
            value_i(t) = d_i * (1 + C(t) - C(t0_i))

        Where: 
        C(t) := cumulative yield integral = ∫ y(s) ds,
                where y(s) is the per-second yield rate (1e18-scaled).

        Define:
            A := totalDeposited = Σ d_i
            B := sumDepositsTimesCumulativeYield = Σ (d_i * C(t0_i))

        Then solvency is:
            S(t) = A + A*C(t) - B

        On deposit of d at time t0:
            A += d
            B += d * C(t0)

        On exit of d originally at t0:
            A -= d
            B -= d * C(t0)
    */

    // =====================================================================
    // STATE VARIABLES
    // =====================================================================

    IERC20Upgradeable public BKNToken;

    uint256 private constant ONE = 1e18;
    uint256 private constant SECONDS_IN_A_YEAR = 365 days;

    bool public isDepositable;
    bool public isClaimable;
    bool public isCompoundable;

    uint256 public yieldPerYear;
    uint256 public yieldPerSecond;

    uint256 public totalDeposited;
    uint256 public yieldUpToDeposit;

    struct UserStake {
        uint256 amountDeposited;
        uint256 latestDepositTimestamp;
    }

    mapping(address => UserStake) public userStakes;

    uint256 public sumDepositsTimesCumulativeYield;

    EnumerableMap.UintToUintMap private yieldSchedule;

    // =====================================================================
    // EVENTS
    // =====================================================================

    /// @notice Emitted when a user makes an initial deposit
    event Deposited(address indexed user, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a user claims principal + interest
    event Claimed(
        address indexed user,
        uint256 principal,
        uint256 interest,
        uint256 timestamp
    );

    /// @notice Emitted when a user compounds interest (and optionally adds more principal)
    event Compounded(
        address indexed user,
        uint256 newPrincipal,
        uint256 interest,
        uint256 timestamp
    );

    /// @notice Emitted when a new yield rate is added to the schedule (APY in 1e18 scale)
    event YieldRateAdded(
        uint256 yieldRate,
        uint256 startTime,
        uint256 timestamp
    );

    /// @notice Emitted when a yield change is removed from the schedule
    event YieldRateRemoved(uint256 startTime, uint256 timestamp);

    // =====================================================================
    // ERRORS
    // =====================================================================

    error DepositsAreClosed();
    error ClaimsAreClosed();
    error CompoundIsClosed();
    error NotEnoughToClaim();
    error NotEnoughToDeposit();
    error ContractHasNotEnoughBalance(uint256 claimingAmount, uint256 balance);
    error AlreadyDeposited(address user);
    error InvalidStartTime();
    error StartTimeMustIncrease();

    uint256[] __gap; // TO-DO update the size of the gap accordingly

    // =====================================================================
    // MODIFIERS
    // =====================================================================

    /// @dev Reverts if deposits are currently disabled
    modifier whenDepositable() {
        if (!isDepositable) {
            revert DepositsAreClosed();
        }
        _;
    }

    /// @dev Reverts if claims are currently disabled
    modifier whenClaimable() {
        if (!isClaimable) {
            revert ClaimsAreClosed();
        }
        _;
    }

    /// @dev Reverts if compound operations are currently disabled
    modifier whenCompoundable() {
        if (!isCompoundable) {
            revert CompoundIsClosed();
        }
        _;
    }

    // =====================================================================
    // INITIALIZATION
    // =====================================================================

        /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Disable all initializers on the implementation contract
        _disableInitializers();
    }


    /// @notice Initialize the staking contract
    /// @param _BKN Address of BKN token
    /// @param _owner Address of owner
        function initialize(address _BKN, address _owner) external initializer {
        // Set staking token
        BKNToken = IERC20Upgradeable(_BKN);

        // Initialize Ownable context and set initial owner to msg.sender
        __Ownable_init();

        // Transfer ownership to the desired owner address
        transferOwnership(_owner);

        // Enable all user operations by default
        isDepositable = true;
        isClaimable = true;
        isCompoundable = true;

        // Set initial yield configuration (15% APY)
        yieldPerYear = 150000000000000000; // 15e16
        yieldPerSecond = yieldPerYear / SECONDS_IN_A_YEAR;
    }


    /// @notice Reinitialize for version 2
    /// @param _BKN Address of BKN token
        function reinitialize(address _BKN) external reinitializer(2) {
        // Update the staking token implementation
        BKNToken = IERC20Upgradeable(_BKN);

        // Align solvency tracking with the previously stored value
        sumDepositsTimesCumulativeYield = yieldUpToDeposit;
    }

    receive() external payable {
        assert(false);
    }

    // =====================================================================
    // ADMIN FUNCTIONS - PAUSE/UNPAUSE
    // =====================================================================

    /// @notice Pause deposits
    function pauseDeposit() external onlyOwner {
        // Disable new deposits
        isDepositable = false;
    }

    /// @notice Unpause deposits
    function unpauseDeposit() external onlyOwner {
        // Enable new deposits
        isDepositable = true;
    }

    /// @notice Pause compound operations
    function pauseCompound() external onlyOwner {
        // Disable compound operations
        isCompoundable = false;
    }

    /// @notice Unpause compound operations
    function unpauseCompound() external onlyOwner {
        // Enable compound operations
        isCompoundable = true;
    }

    /// @notice Pause claims
    function pauseClaim() external onlyOwner {
        // Disable claim operations
        isClaimable = false;
    }

    /// @notice Unpause claims
    function unpauseClaim() external onlyOwner {
        // Enable claim operations
        isClaimable = true;
    }

    // =====================================================================
    // ADMIN FUNCTIONS - TOKEN MANAGEMENT
    // =====================================================================

    /// @notice Remove tokens from contract
    /// @param token Token to remove
    /// @param to Recipient address
    /// @param amount Amount to remove
    function removeTokens(
        IERC20Upgradeable token,
        address to,
        uint256 amount
    ) external onlyOwner {
        // Transfer arbitrary ERC20 tokens out of the staking contract
        token.safeTransfer(to, amount);
    }

    /// @notice Change user stake ownership
    /// @param from Current owner address
    /// @param to New owner address
    function changeUserAddress(address from, address to) external onlyOwner {
        // Move the stake data from one address to another
        UserStake memory stake = userStakes[from];
        userStakes[to] = stake;
        delete userStakes[from];
    }

    // =====================================================================
    // YIELD SCHEDULE MANAGEMENT
    // =====================================================================

    /// @notice Add a yield change starting at `startTime`
    /// @dev Must be called with strictly increasing `startTime` values
    /// @param yieldRatePerYear APY in 1e18 scale (e.g., 15% => 15e16)
    /// @param startTime UNIX timestamp strictly greater than now
    function addYieldChange(
        uint256 yieldRatePerYear,
        uint256 startTime
    ) external onlyOwner {
        // TODO: Add yield rate to schedule
        // HINTS:
        // 1. Validate startTime >= block.timestamp (InvalidStartTime)
        // 2. Calculate ratePerSecond = yieldRatePerYear / SECONDS_IN_A_YEAR
        // 3. Get current schedule length
        // 4. If length > 0, get last start time and verify startTime > lastStart (StartTimeMustIncrease)
        // 5. Set in yieldSchedule map: yieldSchedule.set(startTime, ratePerSecond)
        // 6. Emit YieldRateAdded event
    }

    /// @notice Remove a yield change at an exact `startTime`
    /// @param startTime Timestamp of yield change to remove
    function removeYieldChange(uint256 startTime) external onlyOwner {
        // TODO: Remove yield rate from schedule
        // HINTS:
        // 1. Call yieldSchedule.remove(startTime)
        // 2. Emit YieldRateRemoved event
    }

    /// @notice Get current active yield rate and its start time
    /// @return currentYieldRate Current yield rate per second
    /// @return currentStartTime Start time of current yield rate
    function getCurrentYieldRate()
        public
        view
        returns (uint256 currentYieldRate, uint256 currentStartTime)
    {
        // TODO: Find the latest active yield rate
        // HINTS:
        // 1. Initialize currentYieldRate to yieldPerSecond
        // 2. Initialize currentStartTime to 0
        // 3. Loop through yieldSchedule
        // 4. For each entry, if timestamp > block.timestamp, break
        // 5. Otherwise, update currentYieldRate and currentStartTime
        // 6. Return the values
    }

    // =====================================================================
    // USER FUNCTIONS - DEPOSIT
    // =====================================================================

    /// @notice Deposit principal for user
    /// @param user Address of user depositing
    /// @param amount Amount to deposit
    function deposit(address user, uint256 amount) external whenDepositable {
        // TODO: Implement deposit logic
        // HINTS:
        // 1. Check user hasn't already deposited (AlreadyDeposited error)
        // 2. Transfer amount from user to contract using safeTransferFrom
        // 3. Get current timestamp as t0
        // 4. Create UserStake struct with amount and t0
        // 5. Update totalDeposited: totalDeposited += amount
        // 6. Calculate C(t0) using _cumulativeYield(t0)
        // 7. Update B: sumDepositsTimesCumulativeYield += amount * Ct0
        // 8. Emit Deposited event
    }

    // =====================================================================
    // USER FUNCTIONS - COMPOUND
    // =====================================================================

    /// @notice Compound interest and optionally add more principal
    /// @param user Address of user compounding
    /// @param amount Additional amount to add (0 for just compounding)
    function compoundAndDeposit(
        address user,
        uint256 amount
    ) external whenCompoundable {
        // TODO: Implement compound logic
        // HINTS:
        // 1. Get principal from userStakes[user].amountDeposited
        // 2. If both principal and amount are 0, revert NotEnoughToDeposit
        // 3. If amount > 0, check isDepositable and transfer amount from user
        // 4. Calculate Cnow = _cumulativeYield(block.timestamp)
        // 5. If principal > 0:
        //    a. Get t0 from userStakes[user].latestDepositTimestamp
        //    b. Calculate Ct0 = _cumulativeYield(t0)
        //    c. Calculate interest = Math.mulDiv(principal, (Cnow - Ct0), ONE)
        //    d. Update totalDeposited -= principal
        //    e. Update B: sumDepositsTimesCumulativeYield -= principal * Ct0
        // 6. Calculate newPrincipal = principal + interest + amount
        // 7. Update userStakes with newPrincipal and block.timestamp
        // 8. Update totalDeposited += newPrincipal
        // 9. Update B: sumDepositsTimesCumulativeYield += newPrincipal * Cnow
        // 10. Emit Compounded event
    }

    // =====================================================================
    // USER FUNCTIONS - CLAIM
    // =====================================================================

    /// @notice Claim full balance (principal + simple interest)
    /// @param user Address of user claiming
    function claim(address user) external whenClaimable {
        // TODO: Implement claim logic
        // HINTS:
        // 1. Get principal from userStakes[user].amountDeposited
        // 2. Check principal > 0 (NotEnoughToClaim error)
        // 3. Get t0 from userStakes[user].latestDepositTimestamp
        // 4. Calculate Cnow = _cumulativeYield(block.timestamp)
        // 5. Calculate Ct0 = _cumulativeYield(t0)
        // 6. Calculate interest = Math.mulDiv(principal, (Cnow - Ct0), ONE)
        // 7. Calculate payout = principal + interest
        // 8. Update A: totalDeposited -= principal
        // 9. Update B: sumDepositsTimesCumulativeYield -= principal * Ct0
        // 10. Delete userStakes[user]
        // 11. Check contract has enough balance (ContractHasNotEnoughBalance error)
        // 12. Transfer payout to user using safeTransfer
        // 13. Emit Claimed event
    }

    // =====================================================================
    // VIEW FUNCTIONS
    // =====================================================================

    /// @notice Total liabilities if everyone withdrew now (S(t) = A + A*C(t) - B)
    /// @return Total funds needed to cover all stakes and interest
    function getTotalFundsNeeded() public view returns (uint256) {
        // TODO: Calculate total liabilities
        // HINTS:
        // 1. Calculate Cnow = _cumulativeYield(block.timestamp)
        // 2. Calculate Act = totalDeposited * Cnow
        // 3. Return totalDeposited + Math.mulDiv(1, (Act - sumDepositsTimesCumulativeYield), ONE)
    }

    /// @notice Get net owed amount (liability - assets)
    /// @return Amount owed by contract, or 0 if solvent
    function getNetOwed() external view returns (uint256) {
        // TODO: Calculate net owed
        // HINTS:
        // 1. Calculate currentLiabilities = getTotalFundsNeeded()
        // 2. Get currentAssets = BKNToken.balanceOf(address(this))
        // 3. If currentLiabilities > currentAssets, return difference
        // 4. Otherwise return 0
    }

    /// @notice User withdrawable balance = principal + simple interest
    /// @param user Address of user
    /// @return User's current withdrawable balance
    function getWithdrawableUserBalance(
        address user
    ) public view returns (uint256) {
        // TODO: Calculate user balance with interest
        // HINTS:
        // 1. Get principal from userStakes[user].amountDeposited
        // 2. If principal == 0, return 0
        // 3. Calculate Cnow = _cumulativeYield(block.timestamp)
        // 4. Calculate Ct0 = _cumulativeYield(userStakes[user].latestDepositTimestamp)
        // 5. Calculate interest = Math.mulDiv(principal, (Cnow - Ct0), ONE)
        // 6. Return principal + interest
    }

    // =====================================================================
    // PRIVATE FUNCTIONS
    // =====================================================================

    /// @dev Computes C(t) = ∫y(s)ds from s=0 to s=t, with piecewise y(s)
    /// @param targetTimestamp Target timestamp
    /// @return cumulativeYield Cumulative yield (1e18 * seconds)
    function _cumulativeYield(
        uint256 targetTimestamp
    ) private view returns (uint256 cumulativeYield) {
        // TODO: Calculate cumulative yield at targetTimestamp
        // HINTS:
        // 1. Get schedule length n = yieldSchedule.length()
        // 2. If n == 0, return yieldPerSecond * targetTimestamp
        // 3. Initialize prevStart = 0, prevRate = yieldPerSecond, cumulativeYield = 0
        // 4. Loop through schedule:
        //    a. Get (startTime, rate) from yieldSchedule.at(i)
        //    b. If targetTimestamp <= startTime:
        //       - Add prevRate * (targetTimestamp - prevStart) to cumulativeYield
        //       - Return cumulativeYield
        //    c. Add prevRate * (startTime - prevStart) to cumulativeYield
        //    d. Update prevStart = startTime, prevRate = rate
        // 5. After loop, add prevRate * (targetTimestamp - prevStart) to cumulativeYield
        // 6. Return cumulativeYield
    }
}
