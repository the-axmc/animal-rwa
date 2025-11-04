// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SpeciesOracle.sol";

contract ReportPrice is Script {
    // Call with: --sig "run(address,uint256,uint256)" <oracle> <speciesId> <price8>
    function run(
        address oracleAddr,
        uint256 speciesId,
        uint256 price8
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        SpeciesOracle(oracleAddr).postPrice(speciesId, price8); // price in USD * 1e8
        vm.stopBroadcast();
    }
}
