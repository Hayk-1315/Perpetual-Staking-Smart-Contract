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

    function _assertYieldAt(
        uint256 warpTo,
        uint256 expectedRate,
        uint256 expectedStart
    ) internal {
        vm.warp(warpTo);
        (uint256 rate, uint256 start) = perpetualStaking.getCurrentYieldRate();
        assertEq(rate, expectedRate);
        assertEq(start, expectedStart);
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
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Fix timestamp for deterministic behavior
        vm.warp(1000);

        // Approve and deposit
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Move forward by half a year
        uint256 halfYear = SECONDS_IN_A_YEAR / 2;
        vm.warp(block.timestamp + halfYear);

        // Compute expected interest for half a year at current yieldPerSecond
        uint256 yieldPerSecond = perpetualStaking.yieldPerSecond();
        uint256 deltaC = yieldPerSecond * halfYear;
        uint256 expectedInterest = (amount * deltaC) / 1e18;
        uint256 expectedNewPrincipal = amount + expectedInterest;

        // Compound without adding extra amount
        vm.prank(staker1);
        perpetualStaking.compoundAndDeposit(staker1, 0);

        // Check new principal and timestamp
        (uint256 newPrincipal, uint256 ts) = perpetualStaking.userStakes(
            staker1
        );
        assertEq(newPrincipal, expectedNewPrincipal);
        assertEq(ts, block.timestamp);

        // Global principal should match the new principal
        assertEq(perpetualStaking.totalDeposited(), expectedNewPrincipal);
    }

    function test_compound_with_additional_amount() public {
        uint256 initialAmount = STAKER1_BKN_AMOUNT / 4;
        uint256 extraAmount = STAKER1_BKN_AMOUNT / 4;

        // Fix timestamp for determinism
        vm.warp(1000);

        // Approve enough tokens for initial deposit and extra amount
        vm.prank(staker1);
        bkn.approve(
            address(perpetualStaking),
            initialAmount + extraAmount
        );

        // Initial deposit
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, initialAmount);

        // Move forward by half a year
        uint256 halfYear = SECONDS_IN_A_YEAR / 2;
        vm.warp(block.timestamp + halfYear);

        // Compute expected interest on the initial principal
        uint256 yieldPerSecond = perpetualStaking.yieldPerSecond();
        uint256 deltaC = yieldPerSecond * halfYear;
        uint256 expectedInterest = (initialAmount * deltaC) / 1e18;
        uint256 expectedNewPrincipal = initialAmount + expectedInterest + extraAmount;

        // Compound and add extra amount
        vm.prank(staker1);
        perpetualStaking.compoundAndDeposit(staker1, extraAmount);

        // Check new principal
        (uint256 newPrincipal, ) = perpetualStaking.userStakes(staker1);
        assertEq(newPrincipal, expectedNewPrincipal);
    }

    function test_compound_revert_no_stake_no_amount() public {
        // User has no stake and tries to compound with amount = 0
        vm.prank(staker1);
        vm.expectRevert(PerpetualStaking.NotEnoughToDeposit.selector);
        perpetualStaking.compoundAndDeposit(staker1, 0);
    }

    function test_compound_revert_when_paused() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Approve and deposit first
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Owner pauses compound
        vm.prank(owner);
        perpetualStaking.pauseCompound();

        // Any compound attempt should revert with CompoundIsClosed
        vm.prank(staker1);
        vm.expectRevert(PerpetualStaking.CompoundIsClosed.selector);
        perpetualStaking.compoundAndDeposit(staker1, 0);
    }

    // =====================================================================
    // YIELD SCHEDULE TESTS
    // =====================================================================

    function test_add_yield_change() public {
        // Initial rate should be the base yieldPerSecond
        (uint256 baseRate, uint256 baseStart) = perpetualStaking
            .getCurrentYieldRate();
        assertEq(baseRate, perpetualStaking.yieldPerSecond());
        assertEq(baseStart, 0);

        // Define a future start time and a new yearly rate (20%)
        uint256 startTime = block.timestamp + 1000;
        uint256 newYieldPerYear = 2e17; // 20%
        uint256 expectedRatePerSecond = newYieldPerYear / SECONDS_IN_A_YEAR;

        // Owner schedules the new yield rate
        vm.prank(owner);
        perpetualStaking.addYieldChange(newYieldPerYear, startTime);

        // Before the start time, the current rate should still be the base rate
        vm.warp(startTime - 1);
        (uint256 rateBefore, uint256 startBefore) = perpetualStaking
            .getCurrentYieldRate();
        assertEq(rateBefore, perpetualStaking.yieldPerSecond());
        assertEq(startBefore, 0);

        // After the start time, the current rate should be the new rate
        vm.warp(startTime + 1);
        (uint256 rateAfter, uint256 startAfter) = perpetualStaking
            .getCurrentYieldRate();
        assertEq(rateAfter, expectedRatePerSecond);
        assertEq(startAfter, startTime);
    }

    function test_add_yield_change_revert_past_time() public {
         // Move time forward so we can define a "past" timestamp
        vm.warp(1_000);

        uint256 pastTime = block.timestamp - 1;
        uint256 newYieldPerYear = 2e17; // 20%

        vm.prank(owner);
        vm.expectRevert(PerpetualStaking.InvalidStartTime.selector);
        perpetualStaking.addYieldChange(newYieldPerYear, pastTime);
    }

    function test_add_yield_change_revert_not_increasing() public {
        vm.warp(1_000);

        uint256 T1 = block.timestamp + 100;
        uint256 T2 = T1; // not strictly greater, should revert
        uint256 ratePerYear1 = 2e17; // 20%
        uint256 ratePerYear2 = 25e16; // 25%

        // First yield change at T1 is valid
        vm.prank(owner);
        perpetualStaking.addYieldChange(ratePerYear1, T1);

        // Second yield change with non-increasing timestamp should revert
        vm.prank(owner);
        vm.expectRevert(PerpetualStaking.StartTimeMustIncrease.selector);
        perpetualStaking.addYieldChange(ratePerYear2, T2);
    }

    function test_remove_yield_change() public {
        vm.warp(1_000);

        uint256 startTime = block.timestamp + 100;
        uint256 newYieldPerYear = 2e17; // 20%
        uint256 expectedRatePerSecond = newYieldPerYear / SECONDS_IN_A_YEAR;

        // Add yield change
        vm.prank(owner);
        perpetualStaking.addYieldChange(newYieldPerYear, startTime);

        // After the start time, the new rate should be active
        vm.warp(startTime + 1);
        (uint256 rateAfterAdd, uint256 startAfterAdd) = perpetualStaking
            .getCurrentYieldRate();
        assertEq(rateAfterAdd, expectedRatePerSecond);
        assertEq(startAfterAdd, startTime);

        // Remove the yield change
        vm.prank(owner);
        perpetualStaking.removeYieldChange(startTime);

        // After removal, the contract should fall back to the base rate
        vm.warp(startTime + 2);
        (uint256 rateAfterRemove, uint256 startAfterRemove) = perpetualStaking
            .getCurrentYieldRate();
        assertEq(rateAfterRemove, perpetualStaking.yieldPerSecond());
        assertEq(startAfterRemove, 0);
    }

    function test_multiple_yield_changes() public {
        vm.warp(1_000);

        uint256 baseRate = perpetualStaking.yieldPerSecond();

        uint256 T1 = block.timestamp + 100;
        uint256 T2 = T1 + 100;
        uint256 T3 = T2 + 100;

        uint256 rateSec1 = (2e17) / SECONDS_IN_A_YEAR;   // 20%
        uint256 rateSec2 = (25e16) / SECONDS_IN_A_YEAR;  // 25%
        uint256 rateSec3 = (3e17) / SECONDS_IN_A_YEAR;   // 30%

        vm.prank(owner);
        perpetualStaking.addYieldChange(2e17, T1);

        vm.prank(owner);
        perpetualStaking.addYieldChange(25e16, T2);

        vm.prank(owner);
        perpetualStaking.addYieldChange(3e17, T3);

        _assertYieldAt(T1 - 1, baseRate, 0);
        _assertYieldAt(T1 + 1, rateSec1, T1);
        _assertYieldAt(T2 + 1, rateSec2, T2);
        _assertYieldAt(T3 + 1, rateSec3, T3);
    }

    // =====================================================================
    // VIEW FUNCTIONS TESTS
    // =====================================================================

    function test_get_withdrawable_user_balance_no_time() public {
        // Use a simple deposit amount for the test
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Set a deterministic timestamp for stable assertions
        vm.warp(1000);

        // Approve the staking contract to spend staker1 tokens
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        // Deposit tokens into the staking contract
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Immediately check withdrawable balance (should equal principal)
        uint256 balance = perpetualStaking.getWithdrawableUserBalance(staker1);

        // No time passed, so no interest should be accrued
        assertEq(balance, amount);
    }


    function test_get_withdrawable_user_balance_with_time() public {
        // Use a simple deposit amount for the test
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Set a deterministic timestamp for stable assertions
        vm.warp(1000);

        // Approve the staking contract to spend staker1 tokens
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        // Deposit tokens into the staking contract
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Move time forward by one year to accumulate interest
        vm.warp(block.timestamp + SECONDS_IN_A_YEAR);

        // Check withdrawable balance after time has passed
        uint256 balance = perpetualStaking.getWithdrawableUserBalance(staker1);

        // With one year elapsed, balance should be greater than principal
        assertTrue(balance > amount);
    }

    function test_get_total_funds_needed() public {
        // Define deposit amounts for three different stakers
        uint256 amount1 = STAKER1_BKN_AMOUNT / 2;
        uint256 amount2 = STAKER2_BKN_AMOUNT / 2;
        uint256 amount3 = STAKER3_BKN_AMOUNT / 2;

        // Set a deterministic timestamp for stable assertions
        vm.warp(1000);

        // Approve the staking contract for each staker
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount1);
        vm.prank(staker2);
        bkn.approve(address(perpetualStaking), amount2);
        vm.prank(staker3);
        bkn.approve(address(perpetualStaking), amount3);

        // Deposit tokens for each staker
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount1);
        vm.prank(staker2);
        perpetualStaking.deposit(staker2, amount2);
        vm.prank(staker3);
        perpetualStaking.deposit(staker3, amount3);

        // Move time forward by one year to accumulate interest
        vm.warp(block.timestamp + SECONDS_IN_A_YEAR);

        // Compute total liabilities if everyone withdrew now
        uint256 totalNeeded = perpetualStaking.getTotalFundsNeeded();

        // Sanity check: liabilities should be at least total principal
        assertTrue(totalNeeded >= perpetualStaking.totalDeposited());

        // Sum individual withdrawable balances
        uint256 sumUsers =
            perpetualStaking.getWithdrawableUserBalance(staker1) +
            perpetualStaking.getWithdrawableUserBalance(staker2) +
            perpetualStaking.getWithdrawableUserBalance(staker3);

        // Allow tiny rounding differences between global and per-user calculations
        assertApproxEqAbs(totalNeeded, sumUsers, 2);
    }


    function test_get_current_yield_rate() public {
        // Initially, the active yield rate should be the base yieldPerSecond
        (uint256 rate0, uint256 start0) = perpetualStaking.getCurrentYieldRate();
        assertEq(rate0, perpetualStaking.yieldPerSecond());
        assertEq(start0, 0);

        // Define a future yield change start time
        uint256 startTime = block.timestamp + 1000;

        // Define a new yearly yield rate (20%)
        uint256 newYieldPerYear = 2e17;

        // Convert yearly rate into per-second rate
        uint256 expectedRatePerSecond = newYieldPerYear / SECONDS_IN_A_YEAR;

        // Owner schedules the yield change
        vm.prank(owner);
        perpetualStaking.addYieldChange(newYieldPerYear, startTime);

        // Warp to after the start time so the new rate becomes active
        vm.warp(startTime + 1);

        // Fetch the current active yield rate
        (uint256 rate1, uint256 start1) = perpetualStaking.getCurrentYieldRate();

        // Verify that the new rate is active and the start time matches
        assertEq(rate1, expectedRatePerSecond);
        assertEq(start1, startTime);
                
    }


    function test_get_net_owed() public {
        // Use a simple deposit amount for the test
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Set a deterministic timestamp for stable assertions
        vm.warp(1000);

        // Approve the staking contract to spend staker1 tokens
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        // Deposit tokens into the staking contract
        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Move time forward by one year to accumulate interest
        vm.warp(block.timestamp + SECONDS_IN_A_YEAR);

        // Compute current liabilities
        uint256 liabilities = perpetualStaking.getTotalFundsNeeded();

        // Ensure the contract has enough assets to be solvent
        deal(address(bkn), address(perpetualStaking), liabilities + 1);

        // If solvent, net owed should be zero
        uint256 netOwedSolvent = perpetualStaking.getNetOwed();
        assertEq(netOwedSolvent, 0);

        // Now force insolvency by removing all assets
        deal(address(bkn), address(perpetualStaking), 0);

        // If insolvent, net owed should equal liabilities
        uint256 netOwedInsolvent = perpetualStaking.getNetOwed();
        assertEq(netOwedInsolvent, liabilities);
    }


    // =====================================================================
    // ADMIN FUNCTIONS TESTS
    // =====================================================================

    function test_pause_unpause_deposit() public {
        // Deposits should be enabled by default
        assertTrue(perpetualStaking.isDepositable());

        // Owner pauses deposits
        vm.prank(owner);
        perpetualStaking.pauseDeposit();

        // Deposits should now be disabled
        assertFalse(perpetualStaking.isDepositable());

        // Owner unpauses deposits
        vm.prank(owner);
        perpetualStaking.unpauseDeposit();

        // Deposits should be enabled again
        assertTrue(perpetualStaking.isDepositable());
    }

    function test_pause_unpause_claim() public {
        // Claims should be enabled by default
        assertTrue(perpetualStaking.isClaimable());

        // Owner pauses claims
        vm.prank(owner);
        perpetualStaking.pauseClaim();

        // Claims should now be disabled
        assertFalse(perpetualStaking.isClaimable());

        // Owner unpauses claims
        vm.prank(owner);
        perpetualStaking.unpauseClaim();

        // Claims should be enabled again
        assertTrue(perpetualStaking.isClaimable());
    }

    function test_pause_unpause_compound() public {
        // Compounding should be enabled by default
        assertTrue(perpetualStaking.isCompoundable());

        // Owner pauses compounding
        vm.prank(owner);
        perpetualStaking.pauseCompound();

        // Compounding should now be disabled
        assertFalse(perpetualStaking.isCompoundable());

        // Owner unpauses compounding
        vm.prank(owner);
        perpetualStaking.unpauseCompound();

        // Compounding should be enabled again
        assertTrue(perpetualStaking.isCompoundable());
    }

    function test_remove_tokens() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Approve and deposit to move tokens into the staking contract
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Prepare token interface for removeTokens
        IERC20Upgradeable token = IERC20Upgradeable(address(bkn));

        // Record balances before removal
        uint256 ownerBefore = bkn.balanceOf(owner);
        uint256 contractBefore = bkn.balanceOf(address(perpetualStaking));

        // Owner removes tokens from the staking contract
        vm.prank(owner);
        perpetualStaking.removeTokens(token, owner, amount);

        // Check balances after removal
        uint256 ownerAfter = bkn.balanceOf(owner);
        uint256 contractAfter = bkn.balanceOf(address(perpetualStaking));

        // Owner should receive the removed amount
        assertEq(ownerAfter, ownerBefore + amount);

        // Contract balance should decrease by the removed amount
        assertEq(contractAfter, contractBefore - amount);
    }

    function test_change_user_address() public {
        uint256 amount = STAKER1_BKN_AMOUNT / 2;

        // Set a deterministic timestamp
        vm.warp(1000);

        // Approve and deposit for staker1
        vm.prank(staker1);
        bkn.approve(address(perpetualStaking), amount);

        vm.prank(staker1);
        perpetualStaking.deposit(staker1, amount);

        // Confirm stake exists for staker1
        (uint256 depBefore, uint256 tsBefore) = perpetualStaking.userStakes(staker1);
        assertEq(depBefore, amount);
        assertEq(tsBefore, block.timestamp);

        // Owner changes stake ownership from staker1 to staker2
        vm.prank(owner);
        perpetualStaking.changeUserAddress(staker1, staker2);

        // staker1 stake should be cleared
        (uint256 dep1After, uint256 ts1After) = perpetualStaking.userStakes(staker1);
        assertEq(dep1After, 0);
        assertEq(ts1After, 0);

        // staker2 should now own the stake
        (uint256 dep2After, uint256 ts2After) = perpetualStaking.userStakes(staker2);
        assertEq(dep2After, amount);
        assertEq(ts2After, tsBefore);
    }
}
