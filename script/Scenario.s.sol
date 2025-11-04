// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";

contract Scenario is Script {
    // Call with: --sig "run(address,address,address,address,uint256)"
    // <usdc> <species> <oracle> <lending> <speciesId>
    function run(
        address usdcAddr,
        address speciesAddr,
        address oracleAddr,
        address lendingAddr,
        uint256 speciesId
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);

        MockUSDC usdc = MockUSDC(usdcAddr);
        SpeciesToken species = SpeciesToken(speciesAddr);
        SpeciesOracle oracle = SpeciesOracle(oracleAddr);
        SpeciesLending lending = SpeciesLending(lendingAddr);

        // Mint yourself 10 units of the species
        species.mint(me, speciesId, 10e18, "");

        // Post 3 prices around $12 and accept
        oracle.postPrice(speciesId, 1_200_000_000);
        oracle.postPrice(speciesId, 1_180_000_000);
        oracle.postPrice(speciesId, 1_220_000_000);
        oracle.accept(speciesId);

        // Approve and deposit 5 units
        species.setApprovalForAll(lendingAddr, true);
        lending.deposit(speciesId, 5e18);

        // Fund lending pool with mUSDC so it can lend (top up if needed)
        usdc.mint(lendingAddr, 100_000e6);

        // Borrow $25 (mUSDC has 6 decimals)
        lending.borrow(25e6);

        vm.stopBroadcast();
    }
}
