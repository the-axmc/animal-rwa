// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SpeciesToken.sol";

contract SpeciesTokenTest is Test {
    SpeciesToken token;
    address admin = address(0xA11CE);
    address minter = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        token = new SpeciesToken("ipfs://BASE/{id}.json", admin);

        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.setSpeciesInfo(1, 18, false);
        vm.stopPrank();

        // configure a species
        vm.prank(admin);
        token.setSpeciesInfo(1, 18, false);
    }

    function testRolesAndMintBurn1155() public {
        // non-minter cannot mint
        vm.expectRevert();
        token.mint(user, 1, 1e18, "");

        // minter mints
        vm.prank(minter);
        token.mint(user, 1, 2e18, "");
        assertEq(token.balanceOf(user, 1), 2e18);

        // user can burn their own
        vm.prank(user);
        token.burn(user, 1, 1e18);
        assertEq(token.balanceOf(user, 1), 1e18);
    }

    function testPausePreventsMint() public {
        vm.prank(admin);
        token.setSpeciesInfo(2, 18, true); // paused
        vm.prank(minter);
        vm.expectRevert("MINT_PAUSED");
        token.mint(user, 2, 1e18, "");
    }

    function testSupportsInterface() public view {
        // ERC165 + ERC1155 + AccessControl should be supported
        bool ok165 = token.supportsInterface(0x01ffc9a7);
        bool ok1155 = token.supportsInterface(0xd9b67a26);
        bool okAccess = token.supportsInterface(0x7965db0b); // AccessControl
        require(ok165 && ok1155 && okAccess, "supportsInterface mismatch");
    }
}
