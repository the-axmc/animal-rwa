// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1) Deploy a mock stable (6 decimals) for Fuji testing
        MockUSDC usdc = new MockUSDC();

        // 2) Core contracts
        SpeciesToken species = new SpeciesToken("ipfs://BASE/{id}.json", admin);
        SpeciesOracle oracle = new SpeciesOracle(admin);
        SpeciesLending lending = new SpeciesLending(
            IERC20(address(usdc)),
            species,
            oracle,
            admin
        );

        vm.stopBroadcast();

        console2.log("MockUSDC :", address(usdc));
        console2.log("Species  :", address(species));
        console2.log("Oracle   :", address(oracle));
        console2.log("Lending  :", address(lending));
        console2.log("Admin    :", admin);
    }
}
