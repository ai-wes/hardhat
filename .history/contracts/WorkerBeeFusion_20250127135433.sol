// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/*
   This contract holds the fusion logic, removing it from the main contract.
   It references the main WorkerBeeNFT contract to burn parents and mint fused bees.
*/

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// Minimal interface to call relevant functions on WorkerBeeNFTMain
interface IWorkerBeeNFTFusion {
    function ownerOf(uint256 tokenId) external view returns (address);
    function _burn(uint256 tokenId) external;
    function _mintTierNft(address to, uint8 tier, string memory uri, uint256 paid) external;
    function tierPowerValue(uint8 tier) external pure returns (uint256);
    function beeInfo(uint256 tokenId) external view returns (uint8 tier);
    function beeAttributes(uint256 tokenId) external view returns (
        uint256 ancestryCount,
        uint256 creationBlock,
        uint256 fusionCount,
        string[] memory ancestralTraits,
        uint256 powerLevel,
        uint256[] memory parentTokenIds,
        bool isLegendary,
        uint256 lastInteractionBlock
    );
    function totalMintedOverall() external view returns (uint256);
    function MAX_OVERALL_SUPPLY() external view returns (uint256);
}

contract WorkerBeeFusion is 
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /* ============ Events ============ */
    event BeeFused(uint256[] parentIds, uint256 newTokenId, uint8 newTier);
    event FusionRequested(address indexed user, uint256[] parentIds);

    /* ============ Structs ============ */
    struct PendingFusion {
        address user;
        uint256[] parentIds;
        string fuseURI;
        uint256 totalAncestry;
    }

    // references the WorkerBeeNFTMain for actual storage
    IWorkerBeeNFTFusion public beeMain;

    /* ============ State Variables ============ */
    mapping(uint256 => PendingFusion) public pendingFusions; 
    uint256 public fusionCounter;  // naive approach for "requestId"

    /* ============ Initialize ============ */
    function initialize(address _beeMain) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        beeMain = IWorkerBeeNFTFusion(_beeMain);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ External ============ */
    function fuseBees(uint256[] calldata tokenIds, string calldata fuseURI) 
        external 
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        require(tokenIds.length >= 2, "Need >=2 bees");
        uint256 totalAncestry = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(beeMain.ownerOf(tokenIds[i]) == msg.sender, "Not owner");
            // get ancestry from beeMain
            (
                uint256 ancestryCount,
                ,
                ,
                ,
                ,
                ,
                ,
                
            ) = beeMain.beeAttributes(tokenIds[i]);
            totalAncestry += ancestryCount;
        }

        fusionCounter++;
        pendingFusions[fusionCounter] = PendingFusion({
            user: msg.sender,
            parentIds: tokenIds,
            fuseURI: fuseURI,
            totalAncestry: totalAncestry
        });

        emit FusionRequested(msg.sender, tokenIds);
        return fusionCounter;
    }

    // example final step: could be triggered by some VRF or direct call
    function finalizeFusion(uint256 fusionId) external onlyOwner {
        PendingFusion memory pf = pendingFusions[fusionId];
        require(pf.user != address(0), "Invalid fusion request");

        uint8 newTier = _calculateTierByAncestry(pf.totalAncestry);
        require(beeMain.totalMintedOverall() < beeMain.MAX_OVERALL_SUPPLY(), "Max supply reached");

        // burn parents
        for (uint256 i = 0; i < pf.parentIds.length; i++) {
            beeMain._burn(pf.parentIds[i]);
        }

        // mint new
        beeMain._mintTierNft(pf.user, newTier, pf.fuseURI, 0);

        // optionally get new tokenId by reading total supply or by hooking an event
        // for demonstration, we assume newTokenId is simply beeMain.totalMintedOverall()

        uint256 newTokenId = beeMain.totalMintedOverall(); 
        emit BeeFused(pf.parentIds, newTokenId, newTier);

        delete pendingFusions[fusionId];
    }

    /* ============ Internal Tier Calc ============ */
    // Mirror original " _calculateTierByAncestry(...) "
    function _calculateTierByAncestry(uint256 ancestry) internal pure returns (uint8) {
        // Worker=0, Drone=1, Inquisitor=2, Oracle=3, Queen=4, KingBee=5
        if (ancestry == 3)   return 1;  // Drone
        if (ancestry == 6)   return 2;  // Inquisitor
        if (ancestry == 9)   return 3;  // Oracle
        if (ancestry == 11)  return 4;  // Queen
        if (ancestry >= 100) return 5;  // KingBee
        return 0;                      // Worker
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
