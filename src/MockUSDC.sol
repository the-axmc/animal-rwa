// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20("MockUSDC", "mUSDC") {
    uint8 private constant _DECIMALS = 6;
    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }
    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}
