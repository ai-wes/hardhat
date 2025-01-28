// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/* 
   This contract is responsible for VRF logic, requesting random words,
   storing pending requests, and finalizing those mints using calls into
   the main WorkerBeeNFT contract.
*/

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

// VRF interfaces
import "./interfaces/VRFCoordinatorV2Interface.sol";
import "./interfaces/VRFConsumerBaseV2.sol";

// Minimal interface to call _mintTierNft on WorkerBeeNFTMain
interface IWorkerBeeNFTMain {
    function _mintTierNft(address to, uint8 tier, string memory uri, uint256 paid) external;
    function isDecreeValid(bytes32 decreeId) external view returns (bool);
    function getDecreePrice(bytes32 decreeId, uint256 originalPrice) external view returns (uint256);
    function totalMintedOverall() external view returns (uint256);
    function MAX_OVERALL_SUPPLY() external view returns (uint256);
}

contract WorkerBeeVRF is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VRFConsumerBaseV2
{
    /* ============ Structs ============ */
    struct PendingMint {
        address recipient;
        string uri;
        bytes32 decreeId;
        uint256 paid;
    }

    struct PendingInstantMint {
        address minter;
        uint8 tier;
        uint256 paid;
        string designatedURI;
    }

    /* ============ State Variables ============ */
    IWorkerBeeNFTMain public workerBeeNFTMain;

    bytes32 private vrfKeyHash;
    uint256 private vrfFee;
    uint64 public vrfSubscriptionId;
    VRFCoordinatorV2Interface private COORDINATOR;

    // Mappings for pending requests
    mapping(uint256 => PendingMint) public pendingMints;
    mapping(uint256 => PendingInstantMint) public pendingInstantMints;

    /* ============ Events ============ */
    event MintRequestCreated(address indexed minter, uint8 tier, uint256 requestId);

    constructor(address vrfCoordinator) VRFConsumerBaseV2(vrfCoordinator) {
        _disableInitializers();
    }

    function initialize(
        address _mainContract,
        bytes32 _vrfKeyHash,
        uint256 _vrfFee,
        address vrfCoordinatorAddress,
        uint64 subscriptionId
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        workerBeeNFTMain = IWorkerBeeNFTMain(_mainContract);

        vrfKeyHash = _vrfKeyHash;
        vrfFee = _vrfFee;
        vrfSubscriptionId = subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinatorAddress);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Public Mint via VRF ============ */
    function publicMint(string memory uri, bytes32 decreeId) external payable nonReentrant whenNotPaused {
        // check price from main contract
        uint256 mintCost = workerBeeNFTMain.getDecreePrice(decreeId, 0.01 ether);
        require(msg.value >= mintCost, "Insufficient payment");

        // check overall supply from main
        require(workerBeeNFTMain.totalMintedOverall() < workerBeeNFTMain.MAX_OVERALL_SUPPLY(), "Max supply reached");

        // record usage if decree is valid
        // (in the original code, we increment decree usage here if valid, but you can also
        //  do that upon finalization in main contract if you prefer)
        
        // request VRF
        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            3,
            2000000,
            1
        );

        // store pendingMint
        pendingMints[requestId] = PendingMint({
            recipient: msg.sender,
            uri: uri,
            decreeId: decreeId,
            paid: msg.value
        });
    }

    // Specialized VRF-based mints for higher tiers
    function mintDrone(string calldata uri) external payable nonReentrant whenNotPaused {
        // example pricing
        require(msg.value >= (3 * 0.01 ether * 88)/100, "Not enough ETH for Drone");

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            3,
            2000000,
            1
        );

        pendingInstantMints[requestId] = PendingInstantMint({
            minter: msg.sender,
            tier: 1, // Drone
            paid: msg.value,
            designatedURI: uri
        });

        emit MintRequestCreated(msg.sender, 1, requestId);
    }

    function mintInquisitor(string calldata uri) external payable nonReentrant whenNotPaused {
        require(msg.value >= (6 * 0.01 ether * 88)/100, "Insufficient for Inquisitor");

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            3,
            2000000,
            1
        );

        pendingInstantMints[requestId] = PendingInstantMint({
            minter: msg.sender,
            tier: 2, // Inquisitor
            paid: msg.value,
            designatedURI: uri
        });

        emit MintRequestCreated(msg.sender, 2, requestId);
    }

    function mintOracle(string calldata uri) external payable nonReentrant whenNotPaused {
        require(msg.value >= (9 * 0.01 ether * 88)/100, "Insufficient for Oracle");

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            3,
            2000000,
            1
        );

        pendingInstantMints[requestId] = PendingInstantMint({
            minter: msg.sender,
            tier: 3, // Oracle
            paid: msg.value,
            designatedURI: uri
        });

        emit MintRequestCreated(msg.sender, 3, requestId);
    }

    function mintQueen(string calldata uri) external payable nonReentrant whenNotPaused {
        require(msg.value >= (11 * 0.01 ether * 88)/100, "Insufficient for Queen");

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            3,
            2000000,
            1
        );

        pendingInstantMints[requestId] = PendingInstantMint({
            minter: msg.sender,
            tier: 4, // Queen
            paid: msg.value,
            designatedURI: uri
        });

        emit MintRequestCreated(msg.sender, 4, requestId);
    }

    /* ============ VRF Fulfill ============ */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory /* randomWords */
    ) internal override {
        // 1) If specialized tier (Drone, Inquisitor, Oracle, Queen)
        if (pendingInstantMints[requestId].minter != address(0)) {
            _finalizeInstantMint(requestId);
        }
        // 2) If standard publicMint (Worker or Drone based on supply threshold)
        else if (pendingMints[requestId].recipient != address(0)) {
            _finalizeVrfMint(requestId);
        }
        // else: unknown
    }

    /* ============ Internal finalizations ============ */
    function _finalizeInstantMint(uint256 requestId) internal {
        PendingInstantMint memory pm = pendingInstantMints[requestId];
        require(pm.minter != address(0), "No pending instant mint data");

        // call into main to do the actual NFT mint
        workerBeeNFTMain._mintTierNft(pm.minter, pm.tier, pm.designatedURI, pm.paid);

        delete pendingInstantMints[requestId];
    }

    function _finalizeVrfMint(uint256 requestId) internal {
        PendingMint memory mintData = pendingMints[requestId];
        require(mintData.recipient != address(0), "No VRF mint data");

        // For simplicity: if total minted so far <= some threshold => Drone, else Worker
        // We'll just pick 0 => Worker, 1 => Drone
        // You can refine how you choose the tier based on randomWords if you want
        // For now, let's do the original logic: if total minted is <= EARLY_MINT_DRONE_THRESHOLD => Drone, else Worker
        // We'll interpret that as tier=1 => Drone, tier=0 => Worker

        // example: check main contract supply
        uint256 mintedSoFar = workerBeeNFTMain.totalMintedOverall();
        uint8 assignedTier = (mintedSoFar <= 300) ? 1 : 0; 

        // call into main contract
        workerBeeNFTMain._mintTierNft(mintData.recipient, assignedTier, mintData.uri, mintData.paid);

        // cleanup
        delete pendingMints[requestId];
    }

    /* ============ Pause / Admin ============ */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
    fallback() external payable {}
}
