// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";

contract ConfigureAndScenario is Script {
    struct Params {
        address usdcAddr;
        address speciesAddr;
        address oracleAddr;
        address lendingAddr;
        uint256 speciesId;
        uint8 unitDecimals;
        uint64 heartbeat;
        uint256 maxDeviationBps;
        uint16 ltvBps;
        uint16 liqThresholdBps;
        uint16 liqBonusBps;
        uint256 cap;
        uint256 price1_8;
        uint256 price2_8;
        uint256 price3_8;
        uint256 mintAmount18;
        uint256 depositAmount18;
        uint256 vaultFund6;
        uint256 borrowAmount6;
    }

    // -------- CORE ----------
    function _execute(Params memory p) internal {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1) Species
        SpeciesToken(p.speciesAddr).setSpeciesInfo(
            p.speciesId,
            p.unitDecimals,
            false
        );

        // 2) Oracle
        SpeciesOracle(p.oracleAddr).setConfig(
            p.speciesId,
            p.heartbeat,
            p.maxDeviationBps,
            false
        );
        SpeciesOracle(p.oracleAddr).grantReporter(admin);
        SpeciesOracle(p.oracleAddr).postPrice(p.speciesId, p.price1_8);
        SpeciesOracle(p.oracleAddr).postPrice(p.speciesId, p.price2_8);
        SpeciesOracle(p.oracleAddr).postPrice(p.speciesId, p.price3_8);

        (uint256 px8, , bool ok) = SpeciesOracle(p.oracleAddr).currentPrice(
            p.speciesId
        );
        require(ok, "Oracle NOT_OK");
        SpeciesOracle(p.oracleAddr).accept(p.speciesId);

        // 3) Risk
        SpeciesLending.Risk memory r = SpeciesLending.Risk({
            ltvBps: p.ltvBps,
            liqThresholdBps: p.liqThresholdBps,
            liqBonusBps: p.liqBonusBps,
            cap: p.cap
        });
        SpeciesLending(p.lendingAddr).setRisk(p.speciesId, r);

        // 4) Mint/approve/fund/deposit/borrow
        SpeciesToken(p.speciesAddr).mint(
            admin,
            p.speciesId,
            p.mintAmount18,
            ""
        );
        SpeciesToken(p.speciesAddr).setApprovalForAll(p.lendingAddr, true);

        if (p.vaultFund6 > 0) {
            MockUSDC(p.usdcAddr).mint(p.lendingAddr, p.vaultFund6);
        }
        if (p.depositAmount18 > 0) {
            SpeciesLending(p.lendingAddr).deposit(
                p.speciesId,
                p.depositAmount18
            );
        }
        if (p.borrowAmount6 > 0) {
            SpeciesLending(p.lendingAddr).borrow(p.borrowAmount6);
        }

        vm.stopBroadcast();

        console2.log("== ConfigureAndScenario DONE ==");
        console2.log("speciesId :", p.speciesId);
        console2.log("medianPx8 :", px8);
        console2.log("minted    :", p.mintAmount18);
        console2.log("deposited :", p.depositAmount18);
        console2.log("borrowed  :", p.borrowAmount6);
    }

    // -------- MODE A: PACKED ARGS ----------
    // Call with: --sig "run(address,address,address,address,uint256,bytes)"
    // packed = abi.encode(
    //   uint8 unitDecimals, uint64 heartbeat, uint256 maxDeviationBps,
    //   uint16 ltvBps, uint16 liqThresholdBps, uint16 liqBonusBps, uint256 cap,
    //   uint256 price1_8, uint256 price2_8, uint256 price3_8,
    //   uint256 mintAmount18, uint256 depositAmount18, uint256 vaultFund6, uint256 borrowAmount6
    // )
    function run(
        address usdcAddr,
        address speciesAddr,
        address oracleAddr,
        address lendingAddr,
        uint256 speciesId,
        bytes memory packed
    ) external {
        Params memory p;
        p.usdcAddr = usdcAddr;
        p.speciesAddr = speciesAddr;
        p.oracleAddr = oracleAddr;
        p.lendingAddr = lendingAddr;
        p.speciesId = speciesId;

        (
            p.unitDecimals,
            p.heartbeat,
            p.maxDeviationBps,
            p.ltvBps,
            p.liqThresholdBps,
            p.liqBonusBps,
            p.cap,
            p.price1_8,
            p.price2_8,
            p.price3_8,
            p.mintAmount18,
            p.depositAmount18,
            p.vaultFund6,
            p.borrowAmount6
        ) = abi.decode(
            packed,
            (
                uint8,
                uint64,
                uint256,
                uint16,
                uint16,
                uint16,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256
            )
        );

        _execute(p);
    }

    // -------- MODE B: ENV-ONLY ----------
    // Put everything in env and call with --sig "run()"
    function run() external {
        Params memory p;
        p.usdcAddr = vm.envAddress("USDC");
        p.speciesAddr = vm.envAddress("SPECIES");
        p.oracleAddr = vm.envAddress("ORACLE");
        p.lendingAddr = vm.envAddress("LENDING");
        p.speciesId = vm.envUint("SPECIES_ID");
        p.unitDecimals = uint8(vm.envUint("UNIT_DECIMALS"));
        p.heartbeat = uint64(vm.envUint("HEARTBEAT"));
        p.maxDeviationBps = vm.envUint("MAX_DEV_BPS");
        p.ltvBps = uint16(vm.envUint("LTV_BPS"));
        p.liqThresholdBps = uint16(vm.envUint("LIQ_THRESHOLD_BPS"));
        p.liqBonusBps = uint16(vm.envUint("LIQ_BONUS_BPS"));
        p.cap = vm.envUint("CAP");
        p.price1_8 = vm.envUint("PRICE1_8");
        p.price2_8 = vm.envUint("PRICE2_8");
        p.price3_8 = vm.envUint("PRICE3_8");
        p.mintAmount18 = vm.envUint("MINT_18");
        p.depositAmount18 = vm.envUint("DEPOSIT_18");
        p.vaultFund6 = vm.envUint("VAULT_FUND_6");
        p.borrowAmount6 = vm.envUint("BORROW_6");
        _execute(p);
    }
}
