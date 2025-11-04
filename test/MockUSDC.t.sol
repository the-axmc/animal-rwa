// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";

contract MockUSDCTest is Test {
    function testDecimalsAndMint() public {
        MockUSDC u = new MockUSDC();
        assertEq(u.decimals(), 6);
        u.mint(address(this), 123e6);
        assertEq(u.balanceOf(address(this)), 123e6);
    }
}
