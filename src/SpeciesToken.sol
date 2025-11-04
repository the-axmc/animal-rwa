// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract SpeciesToken is ERC1155, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct SpeciesInfo {
        bool mintPaused;
        uint8 unitDecimals;
    }

    mapping(uint256 => SpeciesInfo) public speciesInfo;

    constructor(string memory baseURI, address admin) ERC1155(baseURI) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function setSpeciesInfo(
        uint256 id,
        uint8 unitDecimals,
        bool mintPaused
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        speciesInfo[id] = SpeciesInfo(mintPaused, unitDecimals);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyRole(MINTER_ROLE) {
        require(!speciesInfo[id].mintPaused, "MINT_PAUSED");
        _mint(to, id, amount, data);
    }

    function burn(address from, uint256 id, uint256 amount) external {
        require(
            from == msg.sender || isApprovedForAll(from, msg.sender),
            "NOT_AUTH"
        );
        _burn(from, id, amount);
    }

    /// 🔧 Multiple inheritance fix
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
