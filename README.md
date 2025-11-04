# Animal-RWA on Avalanche (Fuji)

We built a minimal, audited-by-logic stack for species-backed RWA on Avalanche C-Chain (Fuji):

- ERC-1155 where each tokenId = a species (e.g., CATTLE).

- Oracle with medianization, heartbeat, and deviation guard.

- Lending vault (over-collateralized) with per-species risk params.

- Foundry scripts to deploy, configure, report prices, and run a full scenario.

- Tests for the whole flow (deposit/borrow/liquidate, staleness, guards).

Anti-fragile by design: strict oracles, conservative LTVs, and explicit decimals.

## Architecture

```bash
MockUSDC (6d)      SpeciesToken (ERC-1155)
    |                    |
    |                    | collateral
    |                    v
    |-------->  SpeciesLending  <-------- SpeciesOracle
                         ^                     ^
                         | borrow              | median, guards
                         |                     |
                     end users            reporters + guardian
```

- Species units: 18 decimals

- Oracle price: USD \* 1e8

- Stable (mUSDC): 6 decimals

Value in USD (6d): usd6 = (amount18 _ price8) / 1e20
Liquidation seize (18d): seize18 = repay6 _ (1+bonusBps/1e4) _ 1e20 / (price8 _ 1e4)

## Contracts

1. SpeciesToken.sol (ERC-1155 + AccessControl)

One contract; each id = species (semi-fungible).

**Roles**:

- DEFAULT_ADMIN_ROLE — configure species, grant roles.

- MINTER_ROLE — mint per species.

- PAUSER_ROLE — pause mint per species.

**Key API**:

- setSpeciesInfo(id, unitDecimals, mintPaused)

- mint(to, id, amount, data)

- burn(from, id, amount)

supportsInterface(...) overridden for ERC1155+AccessControl.

Why 1155? One approval for many species, gas-efficient, simple per-species params.

---

2. SpeciesOracle.sol (Medianizer with guards)

- Reporters post prices per species (REPORTER_ROLE).

- Guardian/admin can accept(id) to finalize the current median (GUARDIAN_ROLE).

- Guards:

  - Heartbeat (staleness): price invalid if too old.

  - Deviation vs last accepted: blocks extreme jumps unless you widen band or step prices.

  - Pause per species.

- Ring buffer (size 5) keeps recent reports; median computed over latest observations.

**Key API**:

- setConfig(id, heartbeat, maxDeviationBps, paused)

- grantReporter(addr)

- postPrice(id, price8)

- currentPrice(id) -> (price8, ts, ok)

- accept(id) (requires ok=true)

---

3. SpeciesLending.sol (Vault: deposit/borrow/repay/liquidate)

Over-collateralized borrowing in mUSDC against species collateral.

Per-species Risk:

ltvBps (max borrow %), liqThresholdBps, liqBonusBps, cap.

Uses oracle currentPrice; borrow is blocked if price is stale/invalid.

**Key API**:

- setRisk(id, Risk)

- deposit(id, amount18)

- withdraw(id, amount18) (if HF stays ≥ 1)

- borrow(amount6)

- repay(amount6)

- liquidate(user, id, repayAmt6) (transfers seized collateral at bonus)

---

4. MockUSDC.sol

- Simple 6-decimals ERC20 for Fuji testing.

- mint(to, amt) for funding scenarios.

## How to add more species

1. Define species (1155):

```bash
species.setSpeciesInfo(SPECIES_ID, 18, false);

```

2. Oracle config + roles

```bash
oracle.setConfig(SPECIES_ID, /*heartbeat*/ 86400, /*maxDeviationBps*/ 500, /*paused*/ false);
oracle.grantReporter(ADMIN_OR_REPORTER_WALLET);

```

3. Risk params

```bash
lending.setRisk(SPECIES_ID, SpeciesLending.Risk({
  ltvBps: 4000,          // 40% LTV to start
  liqThresholdBps: 5000, // 50% liq
  liqBonusBps: 700,      // 7% bonus (illiquid)
  cap:  type(uint256).max
}));

```

4. Seed prices (3 quotes) and accept:

```bash
postPrice(SPECIES_ID, /*USD*1e8*/ ...); // 3x
accept(SPECIES_ID);

```

5. Fund liquidity:

- Mint or transfer stable to the lending contract (so borrowers can receive loans).

- Mint species tokens to test users or listing addresses.

**🔒 Deviation guard strategy:**

Keep maxDeviationBps strict (e.g., 5%). If the market moves hard, either:

> Step prices down/up in ≤5% increments and accept each step (preferred), or

> Temporarily widen maxDeviationBps for that species (use sparingly) and then restore strict settings.
