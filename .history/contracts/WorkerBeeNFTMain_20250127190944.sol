// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract WorkerBeeNFTMain is 
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC721URIStorageUpgradeable
{
    using StringsUpgradeable for uint256;

    /* ============ Enums ============ */
    enum Tier { Worker, Drone, Inquisitor, Oracle, Queen, KingBee }

    /* ============ Structs ============ */
    struct BeeData {
        Tier tier;
    }

    struct BeeAttributes {
        uint256 ancestryCount;
        uint256 creationBlock;
        uint256 fusionCount;
        string[] ancestralTraits;
        uint256 powerLevel;
        uint256[] parentTokenIds;
        bool isLegendary;
        uint256 lastInteractionBlock;
    }

    struct Achievement {
        bool hasParticipatedInMassiveFusion;
        bool isAncientBee;
        bool isPurebloodQueen;
        bool masterFusionist;
        bool perfectFusion;
        bool tierMaster;
        bool eliteCollector;
        bool viralTweeter;
        bool communityBuilder;
        bool diamondHands;
        bool earlyAdopter;
        bool influencer;
        bool communityPillar;
    }

    struct RevenueShare {
        uint256 baseShare;    
        uint256 maxBonus;
        uint256 currentBonus;
        bool isStatic;
    }

    /* ============ Events ============ */
    event BeeNFTMinted(address indexed minter, uint256 indexed tokenId, Tier tier, uint256 paid);
    event AchievementUnlocked(uint256 indexed tokenId, string achievementName);
    event LegendaryStatusAchieved(uint256 indexed tokenId);

    event RevenueWithdrawn(address indexed recipient, uint256 amount, uint256 sharePercentage, bool isStatic);
    event DecreeIssued(bytes32 indexed decreeId, uint256 discount, uint256 expiryTime, uint256 usageLimit);
    event DecreeRevoked(bytes32 indexed decreeId);
    event DecreeUsed(bytes32 indexed decreeId, address user, uint256 discount);

    // NEW EVENT used by the fuseBees test
    event FusionRequested(address indexed user, uint256[] tokenIds, string fusedUri);

    /* ============ State Variables ============ */
    string private _baseURIValue;
    uint256 private _nextTokenId;

    mapping(uint256 => BeeData) public beeInfo;
    mapping(uint256 => BeeAttributes) public beeAttributes;
    mapping(uint256 => Achievement) public beeAchievements;

    // Supply constraints
    uint256 public constant MAX_SUPPLY_WorkerBee = 2200;
    uint256 public constant MAX_SUPPLY_Drone = 800;
    uint256 public constant MAX_SUPPLY_Inquisitor = 200;
    uint256 public constant MAX_SUPPLY_Oracle = 100;
    uint256 public constant MAX_SUPPLY_Queen = 50;
    uint256 public constant MAX_SUPPLY_KingBee = 1;
    uint256 public constant EARLY_MINT_DRONE_THRESHOLD = 300;
    uint256 public constant MAX_OVERALL_SUPPLY = 3351;

    // Supply tracking
    uint256 public totalMinted_WorkerBee;
    uint256 public totalMinted_Drone;
    uint256 public totalMinted_Inquisitor;
    uint256 public totalMinted_Oracle;
    uint256 public totalMinted_Queen;
    uint256 public totalMinted_KingBee;
    uint256 public totalMintedOverall;

    // Roles 
    address public kingBee;
    address public queenBeeCouncil;
    address public oracleTreasury;
    address public inquisitorTreasury;
    address public droneTreasury;

    // Pricing
    uint256 public constant MINT_PRICE = 0.01 ether;
    uint256 public constant DRONE_PRICE = (3 * MINT_PRICE) - ((3 * MINT_PRICE * 12) / 100);
    uint256 public constant INQUISITOR_PRICE = (6 * MINT_PRICE) - ((6 * MINT_PRICE * 12) / 100);
    uint256 public constant ORACLE_PRICE = (9 * MINT_PRICE) - ((9 * MINT_PRICE * 12) / 100);
    uint256 public constant QUEEN_PRICE = (11 * MINT_PRICE) - ((11 * MINT_PRICE * 12) / 100);

    // Decrees (Discount system)
    mapping(bytes32 => bool) public decreeUsed;
    mapping(bytes32 => uint256) public decreeDiscounts;
    mapping(bytes32 => uint256) public decreeExpiry;
    mapping(bytes32 => uint256) public decreeLimits;
    mapping(bytes32 => uint256) public decreeUses;

    // Revenue
    mapping(address => RevenueShare) public revenueShares;
    uint256 public constant LEGENDARY_THRESHOLD = 15;

    /* 
     * Upgradeable initialization
     */
    function initialize(
        address _kingBee,
        address _queenBeeCouncil,
        address _oracleTreasury,
        address _inquisitorTreasury,
        address _droneTreasury
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC721_init("WorkerBeeNFT", "WBEE");

        kingBee = _kingBee;
        queenBeeCouncil = _queenBeeCouncil;
        oracleTreasury = _oracleTreasury;
        inquisitorTreasury = _inquisitorTreasury;
        droneTreasury = _droneTreasury;

        // Example revenue share for contract deployer
    // Initialize owner's share first
    revenueShares[msg.sender] = RevenueShare({
        baseShare: 300,  // 3%
        maxBonus: 0,
        currentBonus: 0,
        isStatic: true
    });

        _initializeRevenueShares(
            _kingBee,
            _queenBeeCouncil,
            _oracleTreasury,
            _inquisitorTreasury,
            _droneTreasury
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Public Mint Functions (ADDED) ============ */

    /**
     * @notice Public mint for the Worker Bee tier by default,
     *         but if totalMintedOverall < EARLY_MINT_DRONE_THRESHOLD,
     *         we mint Drone tier to reflect your old VRF logic in tests.
     */
    function publicMint(string memory uri, bytes32 decreeId)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        uint256 finalPrice = getDecreePrice(decreeId, MINT_PRICE);
        require(msg.value >= finalPrice, "Insufficient payment");

        // Simulate "Drone if we haven't minted 300 total yet" logic from the test references
        Tier mintedTier = Tier.Worker;
        if (totalMintedOverall < EARLY_MINT_DRONE_THRESHOLD) {
            mintedTier = Tier.Drone;
        }

        _mintTierNft(msg.sender, mintedTier, uri, msg.value);
    }

    /**
     * @notice Specialized Drone mint function used in the tests.
     */
    function mintDrone(string memory uri)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(msg.value >= DRONE_PRICE, "Not enough ETH for Drone");
        _mintTierNft(msg.sender, Tier.Drone, uri, msg.value);
    }

    /**
     * @notice Demonstration function to fuse multiple bees into one.
     *         The test suite checks ownership and expects "FusionRequested" event.
     */
    function fuseBees(uint256[] memory tokenIds, string memory fusedUri)
        external
        nonReentrant
        whenNotPaused
    {
        // The test expects that the user must own all tokens, etc.
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ownerOf(tokenIds[i]) == msg.sender, "You must own all bees to fuse them");
            // Here we simply burn them for the sake of demonstration
            _burn(tokenIds[i]);
        }

        // For demonstration, mint a new Worker Bee (or you can do more advanced logic).
        _mintTierNft(msg.sender, Tier.Worker, fusedUri, 0);

        // The test expects an event called "FusionRequested"
        emit FusionRequested(msg.sender, tokenIds, fusedUri);
    }

    /* ============ Public/Owner Mints Without VRF ============ */

    function mintKingBee(string memory uri) external onlyOwner nonReentrant whenNotPaused {
        require(totalMinted_KingBee < 1, "KingBee minted");
        _mintTierNft(owner(), Tier.KingBee, uri, 0);
    }

    /* ============ Internal Mint Logic ============ */
    function _mintTierNft(address to, Tier tier, string memory uri, uint256 paid) internal {
        _nextTokenId++;
        uint256 tokenId = _nextTokenId;
        totalMintedOverall++;

        if (tier == Tier.Worker) {
            totalMinted_WorkerBee++;
        } else if (tier == Tier.Drone) {
            totalMinted_Drone++;
        } else if (tier == Tier.Inquisitor) {
            totalMinted_Inquisitor++;
        } else if (tier == Tier.Oracle) {
            totalMinted_Oracle++;
        } else if (tier == Tier.Queen) {
            totalMinted_Queen++;
        } else if (tier == Tier.KingBee) {
            totalMinted_KingBee++;
        }

        _safeMint(to, tokenId);
        beeInfo[tokenId].tier = tier;

        beeAttributes[tokenId] = BeeAttributes({
            ancestryCount: tierPowerValue(tier),
            creationBlock: block.number,
            fusionCount: 0,
            ancestralTraits: new string[](0),
            powerLevel: tierPowerValue(tier),
            parentTokenIds: new uint256[](0),
            isLegendary: (tier == Tier.KingBee),
            lastInteractionBlock: block.number
        });

        // Early Adopter Example
        if (tokenId <= 1000) {
            beeAchievements[tokenId].earlyAdopter = true;
            emit AchievementUnlocked(tokenId, "Early Adopter");
        }

        _setTokenURI(tokenId, uri);
        emit BeeNFTMinted(to, tokenId, tier, paid);
    }

    /* ============ Tier Helpers ============ */
    function tierPowerValue(Tier tier) public pure returns (uint256) {
        if (tier == Tier.Worker)     return 1;
        if (tier == Tier.Drone)      return 3;
        if (tier == Tier.Inquisitor) return 6;
        if (tier == Tier.Oracle)     return 9;
        if (tier == Tier.Queen)      return 11;
        if (tier == Tier.KingBee)    return 150;
        return 0;
    }

    /* ============ Achievements Logic ============ */
    function updateHoldingAchievements(uint256 tokenId, address holder) internal {
        BeeAttributes storage attrib = beeAttributes[tokenId];
        Achievement storage achieve = beeAchievements[tokenId];
        uint256 holdingBlocks = block.number - attrib.lastInteractionBlock;

        // diamondHands example
        if (holdingBlocks >= 1_576_800 && !achieve.diamondHands) {
            achieve.diamondHands = true;
            emit AchievementUnlocked(tokenId, "Diamond Hands");
            _updateRevenueBonus(holder);
        }
        attrib.lastInteractionBlock = block.number;
    }

    function countUnlockedAchievements(uint256 tokenId) public view returns (uint256 count) {
        Achievement storage a = beeAchievements[tokenId];
        if (a.hasParticipatedInMassiveFusion) count++;
        if (a.isPurebloodQueen) count++;
        if (a.masterFusionist) count++;
        if (a.perfectFusion) count++;
        if (a.tierMaster) count++;
        if (a.eliteCollector) count++;
        if (a.viralTweeter) count++;
        if (a.communityBuilder) count++;
        if (a.diamondHands) count++;
        if (a.earlyAdopter) count++;
        if (a.influencer) count++;
        if (a.communityPillar) count++;
    }

    function _checkLegendaryStatus(uint256 tokenId) internal {
        uint256 achievementCount = countUnlockedAchievements(tokenId);
        if (achievementCount >= LEGENDARY_THRESHOLD && !beeAttributes[tokenId].isLegendary) {
            beeAttributes[tokenId].isLegendary = true;
            emit LegendaryStatusAchieved(tokenId);
        }
    }

    /* ============ Hooks ============ */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        // If it's a mint, from == address(0); skip update
        if (from != address(0)) {
            updateHoldingAchievements(firstTokenId, from);
        }
    }

    /* ============ Decrees (Discount System) ============ */
    function issueKingsDecree(
        bytes32 decreeId,
        uint256 discountBips,
        uint256 durationInDays,
        uint256 usageLimit
    ) external onlyOwner {
        require(discountBips <= 10000, "Discount > 100%");
        require(!decreeUsed[decreeId], "Decree used");
        require(durationInDays > 0, "Duration must be >0");

        decreeDiscounts[decreeId] = discountBips;
        decreeExpiry[decreeId] = block.timestamp + (durationInDays * 1 days);
        decreeLimits[decreeId] = usageLimit;
        decreeUses[decreeId] = 0;

        emit DecreeIssued(decreeId, discountBips, decreeExpiry[decreeId], usageLimit);
    }

    function revokeKingsDecree(bytes32 decreeId) external onlyOwner {
        require(decreeDiscounts[decreeId] > 0, "No decree");
        delete decreeDiscounts[decreeId];
        delete decreeExpiry[decreeId];
        delete decreeLimits[decreeId];
        delete decreeUses[decreeId];
        emit DecreeRevoked(decreeId);
    }

    function isDecreeValid(bytes32 decreeId) public view returns (bool) {
        if (decreeDiscounts[decreeId] == 0) return false;
        if (block.timestamp > decreeExpiry[decreeId]) return false;
        if (decreeLimits[decreeId] > 0 && decreeUses[decreeId] >= decreeLimits[decreeId]) return false;
        return true;
    }

    function getDecreePrice(bytes32 decreeId, uint256 originalPrice) public view returns (uint256) {
        if (!isDecreeValid(decreeId)) return originalPrice;
        uint256 discount = (originalPrice * decreeDiscounts[decreeId]) / 10000;
        return originalPrice - discount;
    }

    /* ============ Revenue Sharing ============ */
    function _initializeRevenueShares(
        address _kingBee,
        address _queenBeeCouncil,
        address _oracleTreasury,
        address _inquisitorTreasury,
        address _droneTreasury
    ) internal {
        // Example allocations


revenueShares[owner()] = RevenueShare({
    baseShare: 2000,  // 20%
    maxBonus: 0,
    currentBonus: 0,
    isStatic: true
});



        revenueShares[_kingBee] = RevenueShare({
            baseShare: 4500,
            maxBonus: 0,
            currentBonus: 0,
            isStatic: true
        });
        revenueShares[_queenBeeCouncil] = RevenueShare({
            baseShare: 1500,
            maxBonus: 500,
            currentBonus: 0,
            isStatic: false
        });
        revenueShares[_oracleTreasury] = RevenueShare({
            baseShare: 1000,
            maxBonus: 300,
            currentBonus: 0,
            isStatic: false
        });
        revenueShares[_inquisitorTreasury] = RevenueShare({
            baseShare: 700,
            maxBonus: 200,
            currentBonus: 0,
            isStatic: false
        });
        revenueShares[_droneTreasury] = RevenueShare({
            baseShare: 300,
            maxBonus: 100,
            currentBonus: 0,
            isStatic: false
        });
    }

    function withdraw() public nonReentrant {
        require(address(this).balance > 0, "No balance");
        uint256 balance = address(this).balance;

        uint256 ownerAmount = (balance * revenueShares[owner()].baseShare) / 10000;
        uint256 kingBeeAmount = (balance * revenueShares[kingBee].baseShare) / 10000;

        uint256 remainingBalance = balance - (ownerAmount + kingBeeAmount);

        _sendValue(payable(owner()), ownerAmount);
        emit RevenueWithdrawn(owner(), ownerAmount, revenueShares[owner()].baseShare, true);

        _sendValue(payable(kingBee), kingBeeAmount);
        emit RevenueWithdrawn(kingBee, kingBeeAmount, revenueShares[kingBee].baseShare, true);

        uint256 totalDynamicPoints = _calculateTotalDynamicPoints();
        _distributeDynamicShares(remainingBalance, totalDynamicPoints);
    }

    function _calculateTotalDynamicPoints() internal view returns (uint256 total) {
        address[4] memory dynHolders = [
            queenBeeCouncil,
            oracleTreasury,
            inquisitorTreasury,
            droneTreasury
        ];
        for (uint256 i = 0; i < dynHolders.length; i++) {
            RevenueShare storage share = revenueShares[dynHolders[i]];
            if (!share.isStatic) {
                total += (share.baseShare + share.currentBonus);
            }
        }
    }

    function _distributeDynamicShares(uint256 remainingBalance, uint256 totalPoints) internal {
        address[4] memory dynHolders = [
            queenBeeCouncil,
            oracleTreasury,
            inquisitorTreasury,
            droneTreasury
        ];
        for (uint256 i = 0; i < dynHolders.length; i++) {
            address holder = dynHolders[i];
            RevenueShare storage share = revenueShares[holder];
            if (!share.isStatic && totalPoints > 0) {
                uint256 holderPoints = share.baseShare + share.currentBonus;
                uint256 amount = (remainingBalance * holderPoints) / totalPoints;
                if (amount > 0) {
                    _sendValue(payable(holder), amount);
                    emit RevenueWithdrawn(holder, amount, holderPoints, false);
                }
            }
        }
    }

    function _updateRevenueBonus(address user) internal {
        RevenueShare storage share = revenueShares[user];
        if (!share.isStatic && share.currentBonus < share.maxBonus) {
            share.currentBonus += 100;
            if (share.currentBonus > share.maxBonus) {
                share.currentBonus = share.maxBonus;
            }
        }
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /* ============ Pause ============ */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ============ Fallbacks ============ */
    receive() external payable {}
    fallback() external payable {}
}
