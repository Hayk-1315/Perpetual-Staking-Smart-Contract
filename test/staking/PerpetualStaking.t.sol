// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {PerpetualStaking} from "../../contracts/staking/PerpetualStaking.sol";
import {Brickken} from "../../contracts/token/Brickken.sol";
import {
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract PerpetualStakingTest is Test {
    // =====================================================================
    // STATE VARIABLES
    // =====================================================================

    PerpetualStaking public perpetualStaking;
    Brickken public bkn;

    address public owner = makeAddr("OWNER");
    address public staker1 = makeAddr("STAKER1");
    address public staker2 = makeAddr("STAKER2");
    address public staker3 = makeAddr("STAKER3");

    uint256 public constant OWNER_BKN_AMOUNT = 4_000_000 ether;
    uint256 public constant STAKER1_BKN_AMOUNT = 1_000 ether;
    uint256 public constant STAKER2_BKN_AMOUNT = 2_000 ether;
    uint256 public constant STAKER3_BKN_AMOUNT = 3_000 ether;
    uint256 public constant YIELD_PER_YEAR = 150000000000000000; // 15e16
    uint256 public constant SECONDS_IN_A_YEAR = 365 days;

    // =====================================================================
    // SETUP
    // =====================================================================

    function setUp() public {
        // Deploy BKN token
        bkn = new Brickken();

        // Deploy PerpetualStaking
        perpetualStaking = new PerpetualStaking();

        // Initialize staking with BKN token and owner address
        perpetualStaking.initialize(address(bkn), owner);

        // Allocate BKN balances to owner and stakers
        deal(address(bkn), owner, OWNER_BKN_AMOUNT);
        deal(address(bkn), staker1, STAKER1_BKN_AMOUNT);
        deal(address(bkn), staker2, STAKER2_BKN_AMOUNT);
        deal(address(bkn), staker3, STAKER3_BKN_AMOUNT);

        // Optionally pre-fund the staking contract to cover interest payouts in tests
        deal(address(bkn), address(perpetualStaking), OWNER_BKN_AMOUNT);
    }


    // =====================================================================
    // INITIALIZATION TESTS
    // =====================================================================

    function test_initialization() public {
        // Owner should be set correctly
        assertEq(perpetualStaking.owner(), owner);

        // BKN token address should match the deployed Brickken token
        assertEq(address(perpetualStaking.BKNToken()), address(bkn));

        // Yield per year should be set to the expected constant (15% in 1e18 scale)
        assertEq(perpetualStaking.yieldPerYear(), YIELD_PER_YEAR);

        // Flags should be enabled by default
        assertTrue(perpetualStaking.isDepositable());
        assertTrue(perpetualStaking.isClaimable());
        assertTrue(perpetualStaking.isCompoundable());

        // Yield per second should be derived from yield per year
        uint256 expectedYieldPerSecond = YIELD_PER_YEAR / SECONDS_IN_A_YEAR;
        assertEq(perpetualStaking.yieldPerSecond(), expectedYieldPerSecond);
    }


    // =====================================================================
    // DEPOSIT TESTS
    // =====================================================================

    function test_deposit() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Fix the current block timestamp for deterministic checks
        vm.warp(1000);

        // Approve tokens for the staking contract
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        // Record user balance before deposit
        uint256 balanceBefore = bkn.balanceOf(staker1);

        // Perform the deposit
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Check stored stake data
        (uint256 deposited, uint256 ts) = perpetualStaking.userStakes(staker1);
        assertEq(deposited, amount);
        assertEq(ts, block.timestamp);

        // Check user balance decreased by the deposited amount
        uint256 balanceAfter = bkn.balanceOf(staker1);
        assertEq(balanceAfter, balanceBefore - amount);

        // Check global totalDeposited matches the deposited amount
        assertEq(perpetualStaking.totalDeposited(), amount);
    }


    function test_deposit_revert_already_deposited() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Approve enough tokens for two attempts
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), STAKER1_BKN_AMOUNT);

        // First deposit succeeds
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Second deposit should revert with AlreadyDeposited error
        vm.prank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PerpetualStaking.AlreadyDeposited.selector,
                staker1
            )
        );
        perpetualStaking.deposit(staker1, amount);
    }


    function test_deposit_revert_when_paused() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Owner pauses deposits
        vm.prank(owner);
        perpetualStaking.pauseDeposit();

        // Approve tokens for the staking contract
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        // Deposit should revert with DepositsAreClosed error
        vm.prank(staker1);
        vm.expectRevert(PerpetualStaking.DepositsAreClosed.selector);
        perpetualStaking.deposit(staker1, amount);
    }


    function test_multiple_deposits_different_stakers() public {
        // Amounts for each staker
        uint256 amount1 = STAKER1_BKN_AMOUNT / 2;
        uint256 amount2 = STAKER2_BKN_AMOUNT / 2;
        uint256 amount3 = STAKER3_BKN_AMOUNT / 2;

        // Approve tokens for each staker
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount1);

        vm.prank(staker2);
        bkn.approve(address(perpetualStaking), amount2);

        vm.prank(staker3);
        bkn.approve(address(perpetualStaking), amount3);

        // Perform deposits
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount1);

        vm.prank(staker2);
        perpetualStaking.deposit(staker2, amount2);

        vm.prank(staker3);
        perpetualStaking.deposit(staker3, amount3);

        // Check stakes for each staker
        (uint256 dep1, ) = perpetualStaking.userStakes(staker1);
        (uint256 dep2, ) = perpetualStaking.userStakes(staker2);
        (uint256 dep3, ) = perpetualStaking.userStakes(staker3);

        assertEq(dep1, amount1);
        assertEq(dep2, amount2);
        assertEq(dep3, amount3);

        // Check global totalDeposited is the sum of all deposits
        uint256 expectedTotal = amount1 + amount2 + amount3;
        assertEq(perpetualStaking.totalDeposited(), expectedTotal);
    }

    // =====================================================================
    // CLAIM TESTS
    // =====================================================================

    function test_claim_principal_only() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Fix timestamp for deterministic behavior
        vm.warp(1000);

        // Approve tokens and deposit
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        uint256 balanceBefore = bkn.balanceOf(staker1);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Claim immediately (no time passed, no interest)
        vm.prank(staker1);
        perpetualStaking.claim(staker1);

        // User should recover exactly the principal (net effect = -amount + amount)
        uint256 balanceAfter = bkn.balanceOf(staker1);
        assertEq(balanceAfter, balanceBefore);

        // Stake should be cleared
        (uint256 deposited, uint256 ts) = perpetualStaking.userStakes(staker1);
        assertEq(deposited, 0);
        assertEq(ts, 0);

        // Global principal should be back to zero
        assertEq(perpetualStaking.totalDeposited(), 0);
    }

    function test_claim_with_interest() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Start at a known timestamp
        vm.warp(1000);

        // Approve and deposit
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        uint256 balanceBefore = bkn.balanceOf(staker1);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Move forward by one year
        vm.warp(block.timestamp + SECONDS_IN_A_YEAR);

        // Reproduce the same interest formula as the contract (constant rate case)
        uint256 yieldPerSecond = perpetualStaking.yieldPerSecond();
        uint256 deltaC = yieldPerSecond * SECONDS_IN_A_YEAR;
        uint256 expectedInterest = (amount * deltaC) / 1e18;
        uint256 expectedPayout = amount + expectedInterest;

        // Claim funds
        vm.prank(staker1);
        perpetualStaking.claim(staker1);

        uint256 balanceAfter = bkn.balanceOf(staker1);

        // Net effect on user balance = -amount (deposit) + payout (principal + interest)
        uint256 expectedFinalBalance = balanceBefore - amount + expectedPayout;
        assertEq(balanceAfter, expectedFinalBalance);

        // After claiming, stake and global principal should be cleared
        (uint256 deposited, ) = perpetualStaking.userStakes(staker1);
        assertEq(deposited, 0);
        assertEq(perpetualStaking.totalDeposited(), 0);
    }

    function test_claim_revert_no_stake() public {
        // User has no active stake
        vm.prank(staker1);
        vm.expectRevert(PerpetualStaking.NotEnoughToClaim.selector);
        perpetualStaking.claim(staker1);
    }

    function test_claim_revert_when_paused() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Approve and deposit first
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Owner pauses claims
        vm.prank(owner);
        perpetualStaking.pauseClaim();

        // Claim should revert with ClaimsAreClosed
        vm.prank(staker1);
        vm.expectRevert(PerpetualStaking.ClaimsAreClosed.selector);
        perpetualStaking.claim(staker1);
    }

    function test_claim_revert_insufficient_balance() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;
        
        
        // Fix timestamp for determinism
        vm.warp(1000);

        // Approve and deposit
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Owner empties the contract balance using removeTokens
        IERC20Upgradeable token = IERC20Upgradeable(address(bkn));
        uint256 contractBalance = bkn.balanceOf(address(perpetualStaking));

        vm.prank(owner);
        perpetualStaking.removeTokens(token, owner, contractBalance);

        // Now the contract has 0 BKN; any claim should fail with ContractHasNotEnoughBalance(amount, 0)
        vm.prank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PerpetualStaking.ContractHasNotEnoughBalance.selector,
                amount,
                0
            )
        );
        perpetualStaking.claim(staker1);
    }

    // =====================================================================
    // COMPOUND TESTS
    // =====================================================================

    function test_compound_no_additional_amount() public {
        // TODO: Test compounding without additional deposit
        // HINTS:
        // 1. Deposit amount X
        // 2. Warp forward by SECONDS_IN_A_YEAR / 2
        // 3. Compound with amount = 0
        // 4. Assert new principal = X + interest
        // 5. Assert latestDepositTimestamp updated to now
    }

    function test_compound_with_additional_amount() public {
        // TODO: Test compounding with additional deposit
        // HINTS:
        // 1. Deposit X
        // 2. Warp forward by SECONDS_IN_A_YEAR / 2
        // 3. Compound with additional amount Y
        // 4. Assert new principal = X + interest + Y
    }

    function test_compound_revert_no_stake_no_amount() public {
        // TODO: Test compound reverts with no stake and no amount
    }

    function test_compound_revert_when_paused() public {
        // TODO: Test compound reverts when paused
    }

    // =====================================================================
    // YIELD SCHEDULE TESTS
    // =====================================================================

    function test_add_yield_change() public {
        // TODO: Test adding a yield change
        // HINTS:
        // 1. Owner calls addYieldChange with future timestamp and new rate
        // 2. Assert getCurrentYieldRate still returns old rate
        // 3. Warp to past the new timestamp
        // 4. Assert getCurrentYieldRate returns new rate
    }

    function test_add_yield_change_revert_past_time() public {
        // TODO: Test adding yield change with past timestamp reverts
        // HINTS:
        // - Call addYieldChange with past timestamp
        // - Expect InvalidStartTime error
    }

    function test_add_yield_change_revert_not_increasing() public {
        // TODO: Test adding non-increasing timestamps reverts
        // HINTS:
        // 1. Add yield change at time T
        // 2. Try to add another at time T (or earlier)
        // 3. Expect StartTimeMustIncrease error
    }

    function test_remove_yield_change() public {
        // TODO: Test removing a yield change
        // HINTS:
        // 1. Add yield change
        // 2. Remove it
        // 3. Assert it's no longer in schedule
    }

    function test_multiple_yield_changes() public {
        // TODO: Test multiple yield changes over time
        // HINTS:
        // 1. Add yield change at T1 (20%)
        // 2. Add yield change at T2 (25%)
        // 3. Add yield change at T3 (30%)
        // 4. Warp to each time and verify getCurrentYieldRate returns correct value
    }

    // =====================================================================
    // VIEW FUNCTIONS TESTS
    // =====================================================================

    function test_get_withdrawable_user_balance_no_time() public {
        // TODO: Test getWithdrawableUserBalance immediately after deposit
        // HINTS:
        // - Deposit X
        // - Assert balance = X (no interest yet)
    }

    function test_get_withdrawable_user_balance_with_time() public {
        // TODO: Test getWithdrawableUserBalance after time passes
        // HINTS:
        // 1. Deposit X
        // 2. Warp by 1 year
        // 3. Assert balance > X (with interest)
    }

    function test_get_total_funds_needed() public {
        // TODO: Test getTotalFundsNeeded
        // HINTS:
        // 1. Deposit multiple users
        // 2. Warp forward
        // 3. Assert getTotalFundsNeeded >= totalDeposited
        // 4. Verify calculation is correct
    }

    function test_get_current_yield_rate() public {
        // TODO: Test getCurrentYieldRate
        // HINTS:
        // 1. Initially should return yieldPerSecond
        // 2. After adding yield change and warping, should return new rate
    }

    function test_get_net_owed() public {
        // TODO: Test getNetOwed
        // HINTS:
        // 1. If contract is solvent, should return 0
        // 2. If liabilities > assets, should return difference
    }

    // =====================================================================
    // ADMIN FUNCTIONS TESTS
    // =====================================================================

    function test_pause_unpause_deposit() public {
        // TODO: Test pause/unpause deposit
        // HINTS:
        // - Assert isDepositable starts true
        // - Call pauseDeposit()
        // - Assert isDepositable is false
        // - Call unpauseDeposit()
        // - Assert isDepositable is true
    }

    function test_pause_unpause_claim() public {
        // TODO: Test pause/unpause claim
    }

    function test_pause_unpause_compound() public {
        // TODO: Test pause/unpause compound
    }

    function test_remove_tokens() public {
        // TODO: Test removeTokens
        // HINTS:
        // 1. Deposit to get tokens in contract
        // 2. Owner calls removeTokens
        // 3. Assert tokens were transferred
    }

    function test_change_user_address() public {
        // TODO: Test changeUserAddress
        // HINTS:
        // 1. Deposit as staker1
        // 2. Owner calls changeUserAddress(staker1, staker2)
        // 3. Assert userStakes[staker1] is empty
        // 4. Assert userStakes[staker2] has the stake
    }
}
