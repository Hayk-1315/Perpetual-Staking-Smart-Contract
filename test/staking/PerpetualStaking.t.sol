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
        // TODO: Deploy BKN token
        // TODO: Deploy PerpetualStaking
        // TODO: Initialize PerpetualStaking
        // TODO: Deal BKN tokens to owner, staker1, staker2, staker3
        // TODO: Transfer ownership if needed
        // HINTS:
        // 1. vm.prank(owner) for owner-only operations
        // 2. Use deal() to allocate ERC20 tokens
        // 3. Initialize with owner and BKN address
    }

    // =====================================================================
    // INITIALIZATION TESTS
    // =====================================================================

    function test_initialization() public {
        // TODO: Test that contract initializes correctly
        // HINTS:
        // - Assert owner is set
        // - Assert BKNToken address is correct
        // - Assert yieldPerYear is 15e16
        // - Assert isDepositable, isClaimable, isCompoundable are true
        // - Assert yieldPerSecond = yieldPerYear / SECONDS_IN_A_YEAR
    }

    // =====================================================================
    // DEPOSIT TESTS
    // =====================================================================

    function test_deposit() public {
        // TODO: Test basic deposit
        // HINTS:
        // 1. Approve tokens for contract
        // 2. Call deposit
        // 3. Assert userStakes shows correct amount and timestamp
        // 4. Assert user balance decreased
    }

    function test_deposit_revert_already_deposited() public {
        // TODO: Test that second deposit reverts
        // HINTS:
        // - Deposit once
        // - Try to deposit again
        // - Use vm.expectRevert(abi.encodeWithSelector(...))
    }

    function test_deposit_revert_when_paused() public {
        // TODO: Test deposit reverts when paused
        // HINTS:
        // - Owner calls pauseDeposit()
        // - Try to deposit
        // - Expect DepositsAreClosed error
    }

    function test_multiple_deposits_different_stakers() public {
        // TODO: Test multiple stakers can deposit
        // HINTS:
        // - Deposit for staker1, staker2, staker3
        // - Assert totalDeposited increases correctly
        // - Assert each user's stake is tracked separately
    }

    // =====================================================================
    // CLAIM TESTS
    // =====================================================================

    function test_claim_principal_only() public {
        // TODO: Test claiming immediately after deposit
        // HINTS:
        // 1. Deposit immediately
        // 2. Claim immediately (no time passed, no interest)
        // 3. Assert user receives principal back
        // 4. Assert userStakes[user] is deleted
    }

    function test_claim_with_interest() public {
        // TODO: Test claiming with accumulated interest
        // HINTS:
        // 1. Deposit
        // 2. Warp forward (vm.warp) by SECONDS_IN_A_YEAR
        // 3. Claim
        // 4. Assert user receives principal + interest
        // 5. Calculate expected interest and verify
    }

    function test_claim_revert_no_stake() public {
        // TODO: Test claiming with no stake reverts
        // HINTS:
        // - Try to claim without depositing
        // - Expect NotEnoughToClaim error
    }

    function test_claim_revert_when_paused() public {
        // TODO: Test claim reverts when paused
        // HINTS:
        // - Deposit
        // - Owner calls pauseClaim()
        // - Try to claim
        // - Expect ClaimsAreClosed error
    }

    function test_claim_revert_insufficient_balance() public {
        // TODO: Test claim reverts if contract has insufficient balance
        // HINTS:
        // 1. Deposit
        // 2. Owner removes tokens via removeTokens()
        // 3. Try to claim
        // 4. Expect ContractHasNotEnoughBalance error
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
