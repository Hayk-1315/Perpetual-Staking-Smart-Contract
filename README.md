# Perpetual Staking Smart Contract (Solidity + Foundry)

This repository contains a implementation of a perpetual staking smart contract plus a full Foundry test suite.
It started from a minimal skeleton (contract interface + empty tests) and was extended into a production‑style,
portfolio‑ready project.

The focus of the project is to demonstrate:

- Clean, upgradeable Solidity code.
- Correct interest and solvency accounting over time.
- Careful handling of user funds and admin controls.
- Professional Git workflow (stacked branches and pull requests).
- Solid unit test coverage using Foundry.

---

## 1. Project Overview

**Domain:** Perpetual staking with simple interest and a piecewise yield schedule.  
**Language:** Solidity `<0.9.0` (tested with 0.8.29).  
**Pattern:** Upgradeable contract using OpenZeppelin `OwnableUpgradeable` + `Initializable`.  
**Token:** ERC‑20 staking token (governance / utility style).  
**Tooling:** Foundry (`forge`, `forge-std`), OpenZeppelin contracts (upgradeable and non‑upgradeable).  

At a high level, stakers deposit an ERC‑20 token into the `PerpetualStaking` contract and earn **simple interest**
over time. The APY can change at specific timestamps, and the contract keeps a global solvency model to know,
at any moment, how much it would need to pay out if everyone withdrew.

---

## 2. Main Features

### 2.1 PerpetualStaking contract

Core features implemented in `PerpetualStaking.sol`:

- ✅ **Upgradeable / Ownable**
  - Uses OpenZeppelin upgradeable base contracts.
  - `initialize(address _token, address _owner)` sets the staking token and contract owner.
  - `reinitialize(address _token)` allows updating the token address in version 2 while keeping state consistent.

- ✅ **Staking controls (feature flags)**
  - `isDepositable`, `isClaimable`, `isCompoundable` booleans.
  - Modifiers:
    - `whenDepositable`
    - `whenClaimable`
    - `whenCompoundable`
  - Admin functions to pause/unpause each action:
    - `pauseDeposit` / `unpauseDeposit`
    - `pauseClaim` / `unpauseClaim`
    - `pauseCompound` / `unpauseCompound`

- ✅ **User staking lifecycle**
  - `deposit(address user, uint256 amount)`  
    First‑time deposit for a user. Records principal and timestamp, transfers tokens into the contract,
    and updates the solvency accounting.
  - `compoundAndDeposit(address user, uint256 amount)`  
    - Realises accrued simple interest on the existing principal.  
    - Optionally adds more tokens (`amount`) from the user.  
    - Updates the user stake to a new principal (`oldPrincipal + interest + amount`) with a fresh timestamp.  
    - Keeps the global solvency model consistent.
  - `claim(address user)`  
    - Computes `principal + simple interest` from the last deposit/compound timestamp.  
    - Updates global totals and deletes the user stake.  
    - Transfers the payout to the user, reverting if the contract balance is not sufficient.

- ✅ **Yield schedule management**
  - Global base yield per year (`yieldPerYear`) and per second (`yieldPerSecond`).
  - A time‑ordered yield schedule using `EnumerableMap.UintToUintMap`:
    - `addYieldChange(uint256 yieldRatePerYear, uint256 startTime)`  
      Adds a future yield change (APY per year, converted to per‑second). Enforces strictly increasing start times.
    - `removeYieldChange(uint256 startTime)`  
      Removes a previously scheduled change.
    - `getCurrentYieldRate()`  
      Returns the active yield rate per second and its start timestamp, taking into account the schedule and `yieldPerSecond` as the default.

- ✅ **Solvency model & view functions**

  The contract uses the following model:

  - Let `A` = `totalDeposited` (sum of all principals).
  - Let `C(t)` = cumulative yield integral up to time `t` (scaled in 1e18).  
  - Let `B` = `sumDepositsTimesCumulativeYield` = Σ dᵢ * C(t₀ᵢ) for each user deposit.
  - Then the total liabilities at time `t` are:  
    `S(t) = A + A * C(t) - B`

  Implemented view functions:

  - `getTotalFundsNeeded()`  
    Returns `S(t)` = total funds required if everyone withdrew at the current block timestamp.
  - `getNetOwed()`  
    `max(S(t) - currentBalance, 0)` to know if the contract is under‑collateralized.
  - `getWithdrawableUserBalance(address user)`  
    Returns `principal + simple interest` for a given user at the current timestamp.

  All of this relies on a private helper:

  - `_cumulativeYield(uint256 targetTimestamp)`  
    Computes `C(t)` by integrating the default yield and any scheduled yield changes up to `targetTimestamp`.

- ✅ **Admin token management**
  - `removeTokens(IERC20Upgradeable token, address to, uint256 amount)`  
    Allows the owner to rescue tokens from the contract (used in tests to simulate under‑collateralization).
  - `changeUserAddress(address from, address to)`  
    Moves a stake from one address to another (e.g. KYC changes, account recovery).

- ✅ **Events & custom errors**
  - Events:
    - `Deposited(user, amount, timestamp)`
    - `Claimed(user, principal, interest, timestamp)`
    - `Compounded(user, newPrincipal, interest, timestamp)`
    - `YieldRateAdded(yieldRatePerYear, startTime, timestamp)`
    - `YieldRateRemoved(startTime, timestamp)`
  - Custom errors for clean, gas‑efficient reverts:
    - `DepositsAreClosed()`, `ClaimsAreClosed()`, `CompoundIsClosed()`
    - `NotEnoughToClaim()`, `NotEnoughToDeposit()`
    - `ContractHasNotEnoughBalance(claimingAmount, balance)`
    - `AlreadyDeposited(user)`, `InvalidStartTime()`, `StartTimeMustIncrease()`

---

## 3. Repository Structure

```text
contracts/
  staking/
    PerpetualStaking.sol        # Main staking logic (upgradeable)
  token/
    Brickken.sol                # ERC20 governance-style token used as the staking asset

test/
  staking/
    PerpetualStaking.t.sol      # Full Foundry test suite for staking + basic token test

foundry.toml                     # Foundry configuration (src, test, remappings, etc.)
```

The token contract is a standard ERC‑20 with roles for minting and burning. In this project it is used as the
staking asset for `PerpetualStaking` and as a convenient way to mint balances in tests.

---

## 4. What Was Provided vs. What Was Implemented

This project did **not** start as a finished repository. The initial delivery contained:

- A partially written `PerpetualStaking.sol`:
  - State variables and comments describing the solvency model.
  - Placeholder sections for events, modifiers, initialization, admin functions, user functions,
    yield schedule management and private helpers.
- A skeleton test file `PerpetualStaking.t.sol`:
  - Empty test sections (SETUP, INITIALIZATION, DEPOSIT, CLAIM, COMPOUND, YIELD SCHEDULE, VIEW FUNCTIONS, ADMIN).
- A short README describing the tasks and the requirement of at least 80% coverage.

Implemented work includes:

- All missing logic in `PerpetualStaking.sol`:
  - Events and custom errors.
  - Feature‑flag modifiers.
  - Initialization & re‑initialization logic.
  - Pause / unpause and token management admin functions.
  - Yield schedule storage, validation and lookup functions.
  - Deposit / compound / claim user flows.
  - Solvency and view functions.
  - `_cumulativeYield` integration logic over a piecewise schedule.
- Complete Foundry test suite:
  - Setup and initialization.
  - Deposits (happy path + revert cases).
  - Claims (with and without interest, paused, insufficient balance).
  - Compounding (with and without additional deposits, revert cases).
  - Yield schedule management (add/remove, invalid inputs, multiple schedules).
  - View functions (withdrawable balances, total funds needed, current yield, net owed).
  - Admin functions (pause/unpause, token removal, stake address migration).
  - One extra test around the ERC‑20 token to exercise mint/transfer.
- Coverage:
  - The staking contract is covered well above the 80% requirement (both in lines and branches).
  - Overall project coverage (staking + token) is also above 80%.

The end result is a **fully working staking system** that can be reused or extended in other projects.

---

## 5. How to Run the Project

### 5.1 Requirements

- Foundry installed (`forge` available in your shell).
- A recent version of `git` and a standard Solidity toolchain.

### 5.2 Install dependencies

If you cloned this repository from scratch and the `lib` folder is empty, run:

```bash
forge install
```

or, to install the specific dependencies used here:

```bash
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install OpenZeppelin/openzeppelin-contracts
```

### 5.3 Run tests

```bash
forge test
```

This will compile the contracts and execute the full test suite in `test/staking/PerpetualStaking.t.sol`.

### 5.4 Check coverage

```bash
forge coverage
```

This command produces a line / branch / function coverage report per file and a global summary.  
In this project the staking contract comfortably exceeds the requested **80% coverage**.

---

## 6. Git Workflow Used

Although this repository currently shows the final result on `main`, the implementation was developed using
a **stacked-PR workflow** to simulate a real‑world review process:

- One branch per task:
  - `TASK-1-foundry-configuration`
  - `TASK-2-initial-functions`
  - `TASK-3-Admin-functions`
  - `TASK-4-yield-management-and-user-functions`
  - `TASK-5-view-functions`
  - `TASK-6-unit-tests`
- Each task was implemented on top of the previous one and opened as a pull request.
- Tests were kept green at every step (`forge build`, `forge test`).

This workflow demonstrates familiarity with:

- Incremental development.
- Keeping changesets focused and reviewable.
- Letting CI (or `forge test`) validate each step.

---

## 7. About the Author

This project was implemented by me: **Albert Khudaverdyan**

Highlights:

The goal of this repository is not only to solve a technical exercise, but to show:

- Ability to work from an incomplete spec and finish it end‑to‑end.
- Comfort with upgradeable contracts, events, custom errors, and time‑based yield logic.
- Habit of backing features with tests and coverage, not just “happy path” demos.

If you are a CTO, lead engineer or reviewer and would like more context about the design decisions,
invariants or test strategy used here, feel free to reach out.



