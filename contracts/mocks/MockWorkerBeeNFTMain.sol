// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract MockWorkerBeeNFTMain {
    // Minimal fields, just enough for your tests:
    mapping(uint256 => address) private _owners;

    function setOwnerOf(uint256 tokenId, address newOwner) external {
        _owners[tokenId] = newOwner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }
}
