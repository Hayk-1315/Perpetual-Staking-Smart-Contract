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
        // Intentionally left blank: initialization is handled by initialize()
        // in this challenge context.
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
        // Validate that the start time is not in the past
        if (startTime < block.timestamp) {
            revert InvalidStartTime();
        }

        // Convert yearly yield to per-second yield
        uint256 ratePerSecond = yieldRatePerYear / SECONDS_IN_A_YEAR;

        // Enforce strictly increasing start times in the schedule
        uint256 length = yieldSchedule.length();
        if (length > 0) {
            (uint256 lastStartTime, ) = yieldSchedule.at(length - 1);
            if (startTime <= lastStartTime) {
                revert StartTimeMustIncrease();
            }
        }

        // Store the new yield rate in the schedule
        yieldSchedule.set(startTime, ratePerSecond);

        // Emit event using the yearly rate for easier off-chain readability
        emit YieldRateAdded(yieldRatePerYear, startTime, block.timestamp);
    }

    /// @notice Remove a yield change at an exact `startTime`
    /// @param startTime Timestamp of yield change to remove
       function removeYieldChange(uint256 startTime) external onlyOwner {
        // Remove the yield change entry for the given start time
        yieldSchedule.remove(startTime);

        // Emit event so off-chain systems can track the removal
        emit YieldRateRemoved(startTime, block.timestamp);
    }


    /// @notice Get current active yield rate and its start time
    /// @return currentYieldRate Current yield rate per second
    /// @return currentStartTime Start time of current yield rate
        function getCurrentYieldRate()
        public
        view
        returns (uint256 currentYieldRate, uint256 currentStartTime)
    {
        // Start with the base yield rate
        currentYieldRate = yieldPerSecond;
        currentStartTime = 0;

        uint256 length = yieldSchedule.length();
        for (uint256 i = 0; i < length; ) {
            (uint256 startTime, uint256 ratePerSecond) = yieldSchedule.at(i);

            // If this entry starts in the future, stop iterating
            if (startTime > block.timestamp) {
                break;
            }

            // Otherwise, this is the latest active rate so far
            currentYieldRate = ratePerSecond;
            currentStartTime = startTime;

            unchecked {
                ++i;
            }
        }
    }

    // =====================================================================
    // USER FUNCTIONS - DEPOSIT
    // =====================================================================

    /// @notice Deposit principal for user
    /// @param user Address of user depositing
    /// @param amount Amount to deposit
    function deposit(address user, uint256 amount) external whenDepositable {
        // Ensure the user does not already have an active stake
        if (userStakes[user].amountDeposited > 0) {
            revert AlreadyDeposited(user);
        }

        // Pull tokens from the user into this contract
        BKNToken.safeTransferFrom(user, address(this), amount);

        // Use current block time as the deposit timestamp
        uint256 t0 = block.timestamp;

        // Record the user's stake
        userStakes[user] = UserStake({
            amountDeposited: amount,
            latestDepositTimestamp: t0
        });

        // Update total principal deposited (A)
        totalDeposited += amount;

        // Compute cumulative yield at deposit time C(t0)
        uint256 Ct0 = _cumulativeYield(t0);

        // Update B = Σ d_i * C(t0_i)
        sumDepositsTimesCumulativeYield += amount * Ct0;

        // Emit deposit event for off-chain tracking
        emit Deposited(user, amount, t0);
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
        // Load current principal for the user
        uint256 principal = userStakes[user].amountDeposited;

        // If there is no existing stake and no additional amount, nothing to do
        if (principal == 0 && amount == 0) {
            revert NotEnoughToDeposit();
        }

        // If the user wants to add more principal, ensure deposits are allowed and pull tokens
        if (amount > 0) {
            if (!isDepositable) {
                revert DepositsAreClosed();
            }
            BKNToken.safeTransferFrom(user, address(this), amount);
        }

        // Compute cumulative yield at current time
        uint256 Cnow = _cumulativeYield(block.timestamp);

        uint256 interest = 0;

        if (principal > 0) {
            // If there is an existing stake, close the old position first
            uint256 t0 = userStakes[user].latestDepositTimestamp;
            uint256 Ct0 = _cumulativeYield(t0);

            // Simple interest on the existing principal between t0 and now
            uint256 deltaC = Cnow - Ct0;
            interest = Math.mulDiv(principal, deltaC, ONE);

            // Remove the old principal from the global aggregates
            totalDeposited -= principal;
            sumDepositsTimesCumulativeYield -= principal * Ct0;
        }

        // New principal after compounding interest and adding extra amount
        uint256 newPrincipal = principal + interest + amount;

        // Update user stake with the new principal and current timestamp
        userStakes[user] = UserStake({
            amountDeposited: newPrincipal,
            latestDepositTimestamp: block.timestamp
        });

        // Add the new principal to the global aggregates
        totalDeposited += newPrincipal;
        sumDepositsTimesCumulativeYield += newPrincipal * Cnow;

        // Emit event for off-chain accounting
        emit Compounded(user, newPrincipal, interest, block.timestamp);
    }

    // =====================================================================
    // USER FUNCTIONS - CLAIM
    // =====================================================================

    /// @notice Claim full balance (principal + simple interest)
    /// @param user Address of user claiming
    function claim(address user) external whenClaimable {
        // Load the user's principal
        uint256 principal = userStakes[user].amountDeposited;

        // User must have an active stake
        if (principal == 0) {
            revert NotEnoughToClaim();
        }

        // Load the original deposit timestamp
        uint256 t0 = userStakes[user].latestDepositTimestamp;

        // Compute cumulative yield at now and at deposit time
        uint256 Cnow = _cumulativeYield(block.timestamp);
        uint256 Ct0 = _cumulativeYield(t0);

        // Simple interest earned between t0 and now
        uint256 deltaC = Cnow - Ct0;
        uint256 interest = Math.mulDiv(principal, deltaC, ONE);

        // Total amount owed to the user
        uint256 payout = principal + interest;

        // Update global aggregates: remove the old principal position
        totalDeposited -= principal;
        sumDepositsTimesCumulativeYield -= principal * Ct0;

        // Clear the user's stake
        delete userStakes[user];

        // Ensure the contract has enough tokens to pay the user
        uint256 balance = BKNToken.balanceOf(address(this));
        if (payout > balance) {
            revert ContractHasNotEnoughBalance(payout, balance);
        }

        // Transfer principal + interest to the user
        BKNToken.safeTransfer(user, payout);

        // Emit event for off-chain tracking
        emit Claimed(user, principal, interest, block.timestamp);
    }

    // =====================================================================
    // VIEW FUNCTIONS
    // =====================================================================

    /// @notice Total liabilities if everyone withdrew now (S(t) = A + A*C(t) - B)
    /// @return Total funds needed to cover all stakes and interest
    function getTotalFundsNeeded() public view returns (uint256) {
        // Current cumulative yield C(t) at now
        uint256 Cnow = _cumulativeYield(block.timestamp);

        // A * C(t) with 1e18 scaling
        uint256 Act = totalDeposited * Cnow;

        // (A * C(t) - B) / 1e18 gives the total interest owed
        uint256 interestPart = Math.mulDiv(
            1,
            (Act - sumDepositsTimesCumulativeYield),
            ONE
        );

        // S(t) = A + interestPart
        return totalDeposited + interestPart;
    }

    /// @notice Get net owed amount (liability - assets)
    /// @return Amount owed by contract, or 0 if solvent
    function getNetOwed() external view returns (uint256) {
        // Total amount needed to cover all stakes and interest
        uint256 currentLiabilities = getTotalFundsNeeded();

        // Current token balance held by the contract
        uint256 currentAssets = BKNToken.balanceOf(address(this));

        // If liabilities exceed assets, return the shortfall
        if (currentLiabilities > currentAssets) {
            return currentLiabilities - currentAssets;
        }

        // Otherwise, the contract is solvent (or overfunded)
        return 0;
    }

    /// @notice User withdrawable balance = principal + simple interest
    /// @param user Address of user
    /// @return User's current withdrawable balance
    function getWithdrawableUserBalance(
        address user
    ) public view returns (uint256) {
        // Load the user's principal
        uint256 principal = userStakes[user].amountDeposited;

        // If no active stake, nothing to withdraw
        if (principal == 0) {
            return 0;
        }

        // Compute cumulative yield at now and at the user's last deposit
        uint256 Cnow = _cumulativeYield(block.timestamp);
        uint256 t0 = userStakes[user].latestDepositTimestamp;
        uint256 Ct0 = _cumulativeYield(t0);

        // Simple interest on the user's principal
        uint256 deltaC = Cnow - Ct0;
        uint256 interest = Math.mulDiv(principal, deltaC, ONE);

        // Principal + interest
        return principal + interest;
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
        uint256 n = yieldSchedule.length();

        // If there is no schedule, use the base per-second yield for the whole period
        if (n == 0) {
            return yieldPerSecond * targetTimestamp;
        }

        uint256 prevStart = 0;
        uint256 prevRate = yieldPerSecond;
        cumulativeYield = 0;

        for (uint256 i = 0; i < n; ) {
            (uint256 startTime, uint256 ratePerSecond) = yieldSchedule.at(i);

            // If the target time falls before this change, integrate up to target and return
            if (targetTimestamp <= startTime) {
                cumulativeYield += prevRate * (targetTimestamp - prevStart);
                return cumulativeYield;
            }

            // Integrate from the previous start up to this change
            cumulativeYield += prevRate * (startTime - prevStart);

            // Move to the next interval
            prevStart = startTime;
            prevRate = ratePerSecond;

            unchecked {
                ++i;
            }
        }

        // After processing all changes, integrate from the last change to the target time
        cumulativeYield += prevRate * (targetTimestamp - prevStart);
    }

}