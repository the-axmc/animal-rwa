// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SpeciesToken.sol";
import "../src/SpeciesOracle.sol";
import "../src/SpeciesLending.sol";
import "../src/MockUSDC.sol";

contract SpeciesLendingTest is Test {
    MockUSDC usdc;
    SpeciesToken species;
    SpeciesOracle oracle;
    SpeciesLending lend;

    address admin = address(this);
    address minter = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B); // liquidator

    uint256 constant CATTLE = 1;

    function setUp() public {
        usdc = new MockUSDC();
        species = new SpeciesToken("ipfs://BASE/{id}.json", admin);
        oracle = new SpeciesOracle(admin);
        lend = new SpeciesLending(
            IERC20(address(usdc)),
            species,
            oracle,
            admin
        );

        // roles & config (explicitly as admin)
        vm.startPrank(admin);
        species.setSpeciesInfo(CATTLE, 18, false);
        species.grantRole(species.MINTER_ROLE(), minter);

        // 5% deviation guard, seed ~$12 and accept
        oracle.setConfig(CATTLE, 365 days, 500, false);
        oracle.grantReporter(admin);
        oracle.postPrice(CATTLE, 1_200_000_000); // $12.00
        oracle.postPrice(CATTLE, 1_180_000_000); // $11.80
        oracle.postPrice(CATTLE, 1_220_000_000); // $12.20
        oracle.accept(CATTLE);
        vm.stopPrank();

        // risk params: 50% LTV, 60% liq, 5% bonus
        SpeciesLending.Risk memory r = SpeciesLending.Risk({
            ltvBps: 5000,
            liqThresholdBps: 6000,
            liqBonusBps: 500,
            cap: type(uint256).max
        });
        lend.setRisk(CATTLE, r);

        // mint species to Alice & approve vault
        vm.prank(minter);
        species.mint(alice, CATTLE, 10e18, "");
        vm.prank(alice);
        species.setApprovalForAll(address(lend), true);

        // fund the lending pool so it can lend out
        usdc.mint(address(lend), 1_000_000e6);
    }

    // --- helpers ---

    /// @dev Walks the accepted oracle price down to target in steps <= stepBps (e.g., 500 = 5%),
    /// posting three identical quotes per step and accepting each.
    function _acceptStep(
        uint256 id,
        uint256 targetPx8,
        uint256 stepBps
    ) internal {
        uint256 last = oracle.lastAcceptedPrice(id);
        require(last != 0, "no last price");

        while (last != targetPx8) {
            // move down by at most stepBps per iteration
            uint256 next = last - (last * stepBps) / 10_000;
            if (next < targetPx8) next = targetPx8;

            oracle.postPrice(id, next);
            oracle.postPrice(id, next);
            oracle.postPrice(id, next);

            (uint256 px, , bool ok) = oracle.currentPrice(id);
            assertTrue(ok, "step median not ok");
            assertEq(px, next);

            oracle.accept(id);
            last = next;
        }
    }

    // --- tests ---

    function testDepositAndBorrow() public {
        vm.startPrank(alice);
        // 5 units @ $12 => ~$60 collateral; LTV 50% -> borrow up to ~$30
        lend.deposit(CATTLE, 5e18);
        lend.borrow(25e6); // $25
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 25e6);
    }

    function testWithdrawBlockedByHealth() public {
        vm.startPrank(alice);
        lend.deposit(CATTLE, 5e18);
        lend.borrow(30e6); // max borrow
        // attempt to withdraw should drop HF < 1 → revert
        vm.expectRevert("LOW_HF");
        lend.withdraw(CATTLE, 1e18);
        vm.stopPrank();
    }

    function testStalePricePreventsBorrow() public {
        vm.startPrank(alice);
        lend.deposit(CATTLE, 5e18);
        vm.stopPrank();

        // advance time beyond heartbeat to make price invalid in _values()
        oracle.setConfig(CATTLE, 1 days, 500, false);
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(alice);
        vm.expectRevert(); // _borrowable == 0
        lend.borrow(1e6);
        vm.stopPrank();
    }

    function testLiquidationMathAndFlow() public {
        // Alice deposits & borrows near limit at $12
        vm.startPrank(alice);
        lend.deposit(CATTLE, 5e18); // ~$60
        lend.borrow(30e6); // $30
        vm.stopPrank();

        // Keep strict deviation guard (5%) and step the price down to $7.20
        oracle.setConfig(CATTLE, 365 days, 500, false);
        _acceptStep(CATTLE, 720_000_000, 500); // 12.00 -> 7.20 in <=5% steps

        // Sanity: see what the oracle will use right now (ring-safe)
        (uint256 px8, , bool ok) = oracle.currentPrice(CATTLE);
        assertTrue(ok, "oracle not ok after stepping");

        // Fund Bob and liquidate $10 with 5% bonus
        uint256 repay6 = 10e6;
        usdc.mint(bob, 1000e6);
        vm.startPrank(bob);
        usdc.approve(address(lend), type(uint256).max);
        lend.liquidate(alice, CATTLE, repay6);
        vm.stopPrank();

        // expected seize (18d) = repay6 * (1 + bonusBps/1e4) * 1e20 / (px8 * 1e4)
        (, , uint16 bonusBps, ) = lend.risk(CATTLE); // tuple destructure; ABI returns a tuple, not a struct
        uint256 expectedSeize = (repay6 * (10_000 + bonusBps) * 1e20) /
            (px8 * 10_000);

        uint256 got = species.balanceOf(bob, CATTLE);
        // tight tolerance; math is integer so this should be exact for our params
        assertApproxEqAbs(got, expectedSeize, 2); // allow +/- 2 wei of 18d

        // Alice's debt reduced by $10
        assertEq(lend.debt(alice), 20e6);
    }
}
