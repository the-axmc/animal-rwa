// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SpeciesOracle.sol";

contract SpeciesOracleTest is Test {
    SpeciesOracle oracle;
    address admin = address(this);
    address rep1 = address(0x1111);
    address rep2 = address(0x2222);
    address rep3 = address(0x3333);

    uint256 constant ID = 1;

    function setUp() public {
        oracle = new SpeciesOracle(admin);
        oracle.setConfig(ID, 1 days, 500, false); // 5% deviation band
        oracle.grantReporter(rep1);
        oracle.grantReporter(rep2);
        oracle.grantReporter(rep3);
    }

    function _post(uint256 p1, uint256 p2, uint256 p3) internal {
        vm.prank(rep1);
        oracle.postPrice(ID, p1);
        vm.prank(rep2);
        oracle.postPrice(ID, p2);
        vm.prank(rep3);
        oracle.postPrice(ID, p3);
    }

    function testMedianAndAccept() public {
        _post(1_200_000_000, 1_180_000_000, 1_220_000_000); // $12, $11.8, $12.2 → median $12
        (uint256 px, , bool ok) = oracle.currentPrice(ID);
        assertTrue(ok);
        assertEq(px, 1_200_000_000);

        oracle.accept(ID);
        assertEq(oracle.lastAcceptedPrice(ID), 1_200_000_000);
    }

    function testStalenessFails() public {
        _post(1_000_000_000, 1_000_000_000, 1_000_000_000);
        vm.warp(block.timestamp + 2 days); // beyond heartbeat
        (, , bool ok) = oracle.currentPrice(ID);
        assertFalse(ok);
    }

    function testDeviationGuardUsesLastAccepted() public {
        // seed acceptance at $10.00
        _post(1_000_000_000, 1_020_000_000, 980_000_000);
        oracle.accept(ID);
        assertEq(oracle.lastAcceptedPrice(ID), 1_000_000_000);

        // Now median jumps +20% to $12 => beyond 5% deviation -> should return last accepted and ok=false
        _post(1_200_000_000, 1_210_000_000, 1_190_000_000);
        (uint256 px, , bool ok) = oracle.currentPrice(ID);
        assertEq(px, 1_000_000_000);
        assertFalse(ok);
    }

    function testGuardianPause() public {
        oracle.setConfig(ID, 1 days, 500, true);
        vm.prank(rep1);
        vm.expectRevert("PAUSED");
        oracle.postPrice(ID, 1);
    }
}
