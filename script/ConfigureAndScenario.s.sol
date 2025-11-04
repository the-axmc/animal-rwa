// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";

/// @notice One-shot helper to add a species, configure oracle/risk,
/// seed 3 prices + accept, mint to admin, approve, fund vault, deposit, borrow.
contract ConfigureAndScenario is Script {
    /// @dev Call with --sig "run(address,address,address,address,uint256,uint8,uint64,uint256,uint16,uint16,uint16,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)"
    function run(
        address usdcAddr, // Mock/real USDC (6d)
        address speciesAddr, // SpeciesToken (ERC1155)
        address oracleAddr, // SpeciesOracle
        address lendingAddr, // SpeciesLending
        uint256 speciesId, // e.g. 2 for CHICKEN
        uint8 unitDecimals, // usually 18
        uint64 heartbeat, // e.g. 86400 (24h)
        uint256 maxDeviationBps, // e.g. 500 (5%)
        uint16 ltvBps, // e.g. 4000 (40%)
        uint16 liqThresholdBps, // e.g. 5500 (55%)
        uint16 liqBonusBps, // e.g. 700  (7%)
        uint256 cap, // protocol cap (use type(uint256).max for "no cap")
        uint256 price1_8, // first quote (USD*1e8)
        uint256 price2_8, // second quote
        uint256 price3_8, // third quote
        uint256 mintAmount18, // how many units to mint to caller (18d)
        uint256 depositAmount18, // how many units to deposit (18d)
        uint256 vaultFund6, // how much USDC to fund vault with (6d)
        uint256 borrowAmount6 // how much to borrow (6d)
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        MockUSDC usdc = MockUSDC(usdcAddr);
        SpeciesToken species = SpeciesToken(speciesAddr);
        SpeciesOracle oracle = SpeciesOracle(oracleAddr);
        SpeciesLending lending = SpeciesLending(lendingAddr);

        vm.startBroadcast(pk);

        // 1) Species setup
        species.setSpeciesInfo(speciesId, unitDecimals, false);

        // 2) Oracle config + reporter
        oracle.setConfig(speciesId, heartbeat, maxDeviationBps, false);
        oracle.grantReporter(admin);

        // 3) Lending risk
        SpeciesLending.Risk memory r = SpeciesLending.Risk({
            ltvBps: ltvBps,
            liqThresholdBps: liqThresholdBps,
            liqBonusBps: liqBonusBps,
            cap: cap
        });
        lending.setRisk(speciesId, r);

        // 4) Seed 3 prices and accept
        oracle.postPrice(speciesId, price1_8);
        oracle.postPrice(speciesId, price2_8);
        oracle.postPrice(speciesId, price3_8);

        // Check oracle status before accepting (helpful in prod)
        (uint256 px8, , bool ok) = oracle.currentPrice(speciesId);
        require(ok, "Oracle not OK (stale/deviation); adjust quotes or config");
        oracle.accept(speciesId);

        // 5) Mint species to admin, approve vault
        species.mint(admin, speciesId, mintAmount18, "");
        species.setApprovalForAll(lendingAddr, true);

        // 6) Fund vault with USDC so borrowing succeeds
        if (vaultFund6 > 0) {
            usdc.mint(lendingAddr, vaultFund6);
        }

        // 7) Deposit & borrow
        if (depositAmount18 > 0) {
            lending.deposit(speciesId, depositAmount18);
        }
        if (borrowAmount6 > 0) {
            lending.borrow(borrowAmount6);
        }

        vm.stopBroadcast();

        console2.log("== ConfigureAndScenario done ==");
        console2.log("SpeciesId :", speciesId);
        console2.log("Median px :", px8);
        console2.log("Minted    :", mintAmount18);
        console2.log("Deposited :", depositAmount18);
        console2.log("Borrowed  :", borrowAmount6);
    }
}
