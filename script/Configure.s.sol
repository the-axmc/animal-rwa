// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";

contract Configure is Script {
    function run(
        address speciesAddr,
        address oracleAddr,
        address lendingAddr,
        uint256 speciesId // e.g., 1 for CATTLE
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);

        SpeciesToken species = SpeciesToken(speciesAddr);
        SpeciesOracle oracle = SpeciesOracle(oracleAddr);
        SpeciesLending lending = SpeciesLending(lendingAddr);

        // species setup
        species.setSpeciesInfo(speciesId, 18, false);

        // oracle: 24h heartbeat, 5% deviation, unpaused
        oracle.setConfig(speciesId, 86400, 500, false);
        // grant your admin wallet as reporter
        oracle.grantReporter(admin);

        // risk: 50% LTV, 60% liq threshold, 5% liq bonus, high cap
        SpeciesLending.Risk memory r = SpeciesLending.Risk({
            ltvBps: 5000,
            liqThresholdBps: 6000,
            liqBonusBps: 500,
            cap: type(uint256).max
        });
        lending.setRisk(speciesId, r);

        vm.stopBroadcast();
    }
}
