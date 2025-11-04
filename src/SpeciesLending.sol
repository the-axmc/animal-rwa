// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./SpeciesToken.sol";
import "./SpeciesOracle.sol";

contract SpeciesLending is Ownable, ERC1155Holder {
    struct Risk {
        uint16 ltvBps;
        uint16 liqThresholdBps;
        uint16 liqBonusBps;
        uint256 cap;
    }

    IERC20 public immutable stable;
    SpeciesToken public immutable species;
    SpeciesOracle public immutable oracle;

    mapping(uint256 => Risk) public risk;
    mapping(address => mapping(uint256 => uint256)) public col;
    mapping(address => uint256) public debt;

    // ✅ pass owner_ to Ownable base constructor here
    constructor(
        IERC20 _stable,
        SpeciesToken _species,
        SpeciesOracle _oracle,
        address owner_
    )
        Ownable(owner_) // <— this line fixes the error
    {
        stable = _stable;
        species = _species;
        oracle = _oracle;
        // _transferOwnership(owner_);        // no longer needed; remove if present
    }

    function setRisk(uint256 id, Risk calldata r) external onlyOwner {
        require(r.liqThresholdBps >= r.ltvBps, "BAD_CFG");
        risk[id] = r;
    }

    // --- user actions ---

    function deposit(uint256 id, uint256 amount) external {
        species.safeTransferFrom(msg.sender, address(this), id, amount, "");
        col[msg.sender][id] += amount;
    }

    function withdraw(uint256 id, uint256 amount) external {
        col[msg.sender][id] -= amount;
        require(_health(msg.sender) >= 1e18, "LOW_HF");
        species.safeTransferFrom(address(this), msg.sender, id, amount, "");
    }

    function borrow(uint256 amt6) external {
        require(_borrowable(msg.sender) >= amt6, "EXCEEDS_LTV");
        debt[msg.sender] += amt6;
        require(stable.transfer(msg.sender, amt6), "TRANSFER_FAIL");
    }

    function repay(uint256 amt6) external {
        require(
            stable.transferFrom(msg.sender, address(this), amt6),
            "TRANSFER_FAIL"
        );
        uint256 d = debt[msg.sender];
        debt[msg.sender] = amt6 >= d ? 0 : d - amt6;
    }

    // --- liquidation ---

    function liquidate(
        address user,
        uint256 speciesId,
        uint256 repayAmt6
    ) external {
        // pull stable from liquidator
        require(
            stable.transferFrom(msg.sender, address(this), repayAmt6),
            "TRANSFER_FAIL"
        );

        // price check
        (uint256 px8, , ) = oracle.currentPrice(speciesId);
        require(px8 > 0, "NO_PRICE");

        // seize18 = repay6 * (1 + bonus) * 1e20 / (px8 * 10_000)
        uint256 seize = (repayAmt6 *
            (10_000 + risk[speciesId].liqBonusBps) *
            1e20) / (px8 * 10_000);

        // clamp to user's balance
        uint256 bal = col[user][speciesId];
        if (seize > bal) seize = bal;

        // move collateral and reduce debt
        col[user][speciesId] -= seize;
        species.safeTransferFrom(
            address(this),
            msg.sender,
            speciesId,
            seize,
            ""
        );

        uint256 d = debt[user];
        debt[user] = repayAmt6 >= d ? 0 : d - repayAmt6;
    }

    // --- views ---

    function _borrowable(address u) internal view returns (uint256) {
        (uint256 b, , ) = _values(u);
        uint256 d = debt[u];
        return b > d ? b - d : 0;
    }

    function _health(address u) internal view returns (uint256) {
        (, uint256 liq, ) = _values(u);
        uint256 d = debt[u];
        if (d == 0) return type(uint256).max;
        return (liq * 1e18) / d;
    }

    function _values(
        address u
    ) internal view returns (uint256 borrowCap6, uint256 liqVal6, bool any) {
        // NOTE: For demo, we loop first 3 species IDs. In prod, track user sets.
        for (uint256 id = 1; id <= 3; id++) {
            uint256 amt = col[u][id];
            if (amt == 0) continue;
            (uint256 px8, , bool valid) = oracle.currentPrice(id);
            if (!valid) continue;
            any = true;
            // USD value in 6d: amt(18d) * px(8d) -> 26d; downscale to 6d => /1e20
            uint256 usd6 = (amt * px8) / 1e20;
            Risk memory r = risk[id];
            borrowCap6 += (usd6 * r.ltvBps) / 10_000;
            liqVal6 += (usd6 * r.liqThresholdBps) / 10_000;
        }
    }
}
