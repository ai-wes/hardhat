// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

// Chainlink VRF
import "./interfaces/VRFCoordinatorV2Interface.sol";
import "./interfaces/VRFConsumerBaseV2.sol";

/* ============ Interface to Main Contract ============ */
interface IWorkerBeeNFTMain {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract WorkerBeeNFTAncillary is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VRFConsumerBaseV2
{
    using StringsUpgradeable for uint256;

    /* ============ Enums ============ */
    enum TokenType { AuraReroll, ItemDrop, TraitReroll, ColorReroll, EffectReroll }
    enum AuraRarity { Common, Uncommon, Rare, Epic, Legendary, Mythic }

    /* ============ Structs ============ */

    // Sub-struct for items
    struct Item {
        string name;
        uint256 rarity;
        uint256 duration;
        uint256 expiryTime;
        uint256 honeyBoost;
        bool isActive;
        ItemVisualEffect visualEffect;
    }

    struct ItemVisualEffect {
        uint256 particleIntensity;
        uint256 colorScheme;
        uint256 patternType;
        uint256 glowIntensity;
    }

    // The main struct for each tokenId's honey system
    struct HoneySystem {
        uint256 honeyLevel;       // current honey level
        uint256 lastUpdateTime;   // last timestamp honey was updated
        mapping(uint256 => Item) items; // itemId -> Item struct
        uint256[] activeItems;    // array of active itemIds
        uint256 achievementBonus; // optional bonus from achievements
    }

    struct VisualTraits {
        uint256 wingType;
        uint256 crownType;
        uint256 bodyPattern;
        uint256 baseColor;
    }

    struct AuraEffect {
        uint256 auraType;
        AuraRarity rarity;
        bytes3 primaryColor;
        uint256 intensity;
        uint256 speed;
        bool isDualColor;
        uint256 specialEffect;
    }

    struct AuraCombo {
        uint256 auraType;
        bytes3 primaryColor;
        bytes3 secondaryColor;
        bool isDualColor;
    }

    // For dynamic token pricing
    struct TokenPricing {
        uint256 basePrice;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 currentPrice;
        uint256 lastPurchaseTime;
        uint256 priceChangeRate;
    }

    struct MarketMetrics {
        uint256 purchasesLast24h;
        uint256 lastUpdateTime;
        mapping(address => uint256) userPurchases;
    }

    // For VRF-based item drops or aura rerolls
    struct PendingReroll {
        address user;
        uint256 tokenId;
        bytes32 attributeToReroll;
    }

    struct DropData {
        uint256 tokenId;
        TokenType dropType;
    }

    /* ============ State Variables ============ */

    // Reference to main contract
    IWorkerBeeNFTMain public mainContract;

    // The honey system, aura, and visuals for each token
    mapping(uint256 => HoneySystem) private beeHoney;
    mapping(uint256 => VisualTraits) private beeVisuals;
    mapping(uint256 => AuraEffect) public beeAuras;

    // VRF configuration
    VRFCoordinatorV2Interface private COORDINATOR;
    address private vrfCoordinator;
    bytes32 private vrfKeyHash;
    uint64 private vrfSubscriptionId;
    uint32  private vrfCallbackGasLimit; 
    uint16 private vrfRequestConfirmations;

    // Decay
    uint256 public constant DAILY_DECAY_RATE = 2;      // e.g. 2% per day
    uint256 public constant HONEY_BOOST_COST = 0.0005 ether;
    uint256 private constant MAX_HONEY_LEVEL = 100;
    uint256 private constant MIN_HONEY_FOR_REWARDS = 20;

    // Aura rarity chance
    uint256 private constant COMMON_AURA_CHANCE     = 5000; // 50%
    uint256 private constant UNCOMMON_AURA_CHANCE   = 2500; // 25%
    uint256 private constant RARE_AURA_CHANCE       = 1500; // 15%
    uint256 private constant EPIC_AURA_CHANCE       = 700;  // 7%
    uint256 private constant LEGENDARY_AURA_CHANCE  = 300;  // 3%


    // Utility token purchases, dynamic pricing
    mapping(TokenType => TokenPricing) public tokenPrices;
    mapping(TokenType => MarketMetrics) public marketMetrics;
    mapping(address => mapping(TokenType => uint256)) public userTokenBalances;

    // VRF pending data
    mapping(bytes32 => DropData) public pendingDrops;
    mapping(uint256 => PendingReroll) public pendingRerolls;

    /* ============ Events ============ */
    event HoneyLevelUpdated(uint256 indexed tokenId, uint256 newLevel);
    event ItemExpired(uint256 indexed tokenId, uint256 indexed itemId);
    event AuraGenerated(uint256 indexed tokenId, uint256 auraType, AuraRarity rarity);
    event AuraEvolved(uint256 indexed tokenId, AuraRarity oldRarity, AuraRarity newRarity);
    event MythicAuraCreated(uint256 indexed tokenId);

    event TokenPurchased(address indexed buyer, TokenType tokenType, uint256 amount, uint256 price);
    event TokenUsed(address indexed user, TokenType tokenType, uint256 tokenId);
    event AuraRerolled(uint256 indexed tokenId, AuraRarity oldRarity, AuraRarity newRarity);
    event ItemDropped(uint256 indexed tokenId, uint256 itemId, uint256 rarity);
    event PriceUpdated(TokenType tokenType, uint256 newPrice);

    /* ============ Modifiers ============ */
    modifier onlyTokenOwner(uint256 tokenId) {
        require(mainContract.ownerOf(tokenId) == msg.sender, "Not token owner");
        _;
    }

    /* ============ Constructor & Initialize ============ */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() VRFConsumerBaseV2(address(0)) {
        _disableInitializers();
    }

    function initialize(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32  _callbackGasLimit,
        uint16 _requestConfirmations
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        vrfCoordinator          = _vrfCoordinator;
        vrfKeyHash              = _keyHash;
        vrfSubscriptionId       = _subscriptionId;
        vrfCallbackGasLimit     = _callbackGasLimit;
        vrfRequestConfirmations = _requestConfirmations;

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Linking to Main Contract ============ */
    function setMainContract(address _mainContract) external onlyOwner {
        mainContract = IWorkerBeeNFTMain(_mainContract);
    }

    /* ============ Pausing ============ */
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ============ Honey Decay Logic ============ */

    function updateHoneyLevel(uint256 tokenId) public {
        // Make sure the token actually exists
        require(mainContract.ownerOf(tokenId) != address(0), "No token");
        
        HoneySystem storage honeySystem = beeHoney[tokenId];

        uint256 elapsed = block.timestamp - honeySystem.lastUpdateTime;
        if (elapsed > 0) {
            uint256 daysElapsed = elapsed / 1 days; // integer # of days
            if (daysElapsed > 0) {
                // e.g. 2% * daysElapsed
                uint256 decayPercent = DAILY_DECAY_RATE * daysElapsed;

                // If you want an achievement bonus that reduces decay, do something like:
                uint256 totalBonus = honeySystem.achievementBonus;
                // net decay = decayPercent * (100 - totalBonus)/100
                uint256 effectiveDecay = (decayPercent * (100 - totalBonus)) / 100;

                uint256 decayAmount = (honeySystem.honeyLevel * effectiveDecay) / 100;
                if (decayAmount >= honeySystem.honeyLevel) {
                    honeySystem.honeyLevel = 0;
                } else {
                    honeySystem.honeyLevel -= decayAmount;
                }
            }
            // Process items for potential honey boosts
            _processActiveItems(tokenId);

            // set lastUpdateTime to now
            honeySystem.lastUpdateTime = block.timestamp;

            emit HoneyLevelUpdated(tokenId, honeySystem.honeyLevel);
        }
    }

    function boostHoney(uint256 tokenId) external payable onlyTokenOwner(tokenId) {
        require(msg.value >= HONEY_BOOST_COST, "Not enough ETH");

        // Decay first
        updateHoneyLevel(tokenId);

        // Then add +10
        HoneySystem storage honeySystem = beeHoney[tokenId];
        uint256 newLevel = honeySystem.honeyLevel + 10;
        honeySystem.honeyLevel = (newLevel > MAX_HONEY_LEVEL) ? MAX_HONEY_LEVEL : newLevel;

        emit HoneyLevelUpdated(tokenId, honeySystem.honeyLevel);
    }


    function boostHoneyCustom(uint256 tokenId, uint256 amount) external payable onlyTokenOwner(tokenId) {

        updateHoneyLevel(tokenId);
        HoneySystem storage honeySystem = beeHoney[tokenId];

        uint256 newLevel = honeySystem.honeyLevel + amount;
        honeySystem.honeyLevel = (newLevel > MAX_HONEY_LEVEL) ? MAX_HONEY_LEVEL : newLevel;

        emit HoneyLevelUpdated(tokenId, honeySystem.honeyLevel);
    }

    function _processActiveItems(uint256 tokenId) internal {
        HoneySystem storage honeySystem = beeHoney[tokenId];
        uint256[] storage activeItems = honeySystem.activeItems;

        // We iterate in reverse to remove expired items
        for (uint256 i = activeItems.length; i > 0; i--) {
            uint256 itemId = activeItems[i - 1];
            Item storage item = honeySystem.items[itemId];

            if (item.expiryTime != 0 && block.timestamp > item.expiryTime) {
                // remove from activeItems
                activeItems[i - 1] = activeItems[activeItems.length - 1];
                activeItems.pop();
                item.isActive = false;

                emit ItemExpired(tokenId, itemId);
            } else {
                // item is active => apply honey boost
                honeySystem.honeyLevel += item.honeyBoost;
                if (honeySystem.honeyLevel > MAX_HONEY_LEVEL) {
                    honeySystem.honeyLevel = MAX_HONEY_LEVEL;
                }
            }
        }
    }

    function _generateRandomItem(uint256 tokenId, uint256 randomness) internal returns (uint256) {
        uint256 rarityRoll = uint256(keccak256(abi.encode(randomness, "ITEM_RARITY"))) % 100;
        uint256 itemRarity;
        if (rarityRoll < 50)      itemRarity = 1;
        else if (rarityRoll < 80) itemRarity = 2;
        else if (rarityRoll < 95) itemRarity = 3;
        else                      itemRarity = 4;

        return _createItem(tokenId, itemRarity, randomness);
    }

    function _createItem(uint256 tokenId, uint256 itemRarity, uint256 randomness) internal returns (uint256) {
        // itemId is pseudo-random
        uint256 itemId = uint256(keccak256(abi.encode(tokenId, randomness, block.timestamp))) % 1e16;

        Item storage itemRef = beeHoney[tokenId].items[itemId];
        itemRef.name = "RandomItem";
        itemRef.rarity = itemRarity;
        itemRef.duration = 1 days;
        itemRef.expiryTime = block.timestamp + 1 days;
        itemRef.honeyBoost = 5;
        itemRef.isActive = true;
        itemRef.visualEffect = ItemVisualEffect({
            particleIntensity: 5,
            colorScheme: 1,
            patternType: 2,
            glowIntensity: 3
        });

        beeHoney[tokenId].activeItems.push(itemId);
        return itemId;
    }

    // Aura generation
    function _generateAuraEffect(uint256 randomness) internal pure returns (AuraEffect memory) {
        uint256 rarityRoll = uint256(keccak256(abi.encode(randomness, "RARITY"))) % 10000;
        AuraRarity auraRarity;
        if (rarityRoll < LEGENDARY_AURA_CHANCE) {
            auraRarity = AuraRarity.Legendary;
        } else if (rarityRoll < LEGENDARY_AURA_CHANCE + EPIC_AURA_CHANCE) {
            auraRarity = AuraRarity.Epic;
        } else if (rarityRoll < LEGENDARY_AURA_CHANCE + EPIC_AURA_CHANCE + RARE_AURA_CHANCE) {
            auraRarity = AuraRarity.Rare;
        } else if (rarityRoll < LEGENDARY_AURA_CHANCE + EPIC_AURA_CHANCE + RARE_AURA_CHANCE + UNCOMMON_AURA_CHANCE) {
            auraRarity = AuraRarity.Uncommon;
        } else {
            auraRarity = AuraRarity.Common;
        }

        uint256 auraType = uint256(keccak256(abi.encode(randomness, "TYPE"))) % 15 + 1;
        bytes3 primaryColor   = _randomColor(auraRarity, randomness);

        bool isDualColor = (auraRarity >= AuraRarity.Rare) &&
                           ((uint256(keccak256(abi.encode(randomness, "DUAL"))) % 100) < 50);

        uint256 baseIntensity = 50 + uint256(auraRarity) * 10;
        uint256 baseSpeed     = 50 + uint256(auraRarity) * 10;
        uint256 intensity     = baseIntensity + (uint256(keccak256(abi.encode(randomness, "INTENSITY"))) % (100 - baseIntensity));
        uint256 speed         = baseSpeed + (uint256(keccak256(abi.encode(randomness, "SPEED"))) % (100 - baseSpeed));

        if (intensity > 100) intensity = 100;
        if (speed > 100)     speed = 100;

        AuraEffect memory aura = AuraEffect({
            auraType: auraType,
            rarity: auraRarity,
            primaryColor: primaryColor,
            intensity: intensity,
            speed: speed,
            isDualColor: isDualColor,
            specialEffect: uint256(auraRarity)
        });

        return aura;
    }

    function _randomColor(AuraRarity /*rarity*/, uint256 seed) internal pure returns (bytes3) {
        uint256 rand = uint256(keccak256(abi.encode(seed, "COLOR")));
        return bytes3(uint24(rand % 0xFFFFFF));
    }



    /* ============ Token Purchase, Rerolls, Drops ============ */

    function initializeTokenPricing() external onlyOwner {
        tokenPrices[TokenType.AuraReroll] = TokenPricing({
            basePrice: 0.01 ether,
            maxPrice: 0.05 ether,
            minPrice: 0.005 ether,
            currentPrice: 0.01 ether,
            lastPurchaseTime: block.timestamp,
            priceChangeRate: 1 hours
        });
        tokenPrices[TokenType.ItemDrop] = TokenPricing({
            basePrice: 0.015 ether,
            maxPrice: 0.075 ether,
            minPrice: 0.0075 ether,
            currentPrice: 0.015 ether,
            lastPurchaseTime: block.timestamp,
            priceChangeRate: 1 hours
        });
    }

    function purchaseTokens(TokenType tokenType, uint256 amount) external payable nonReentrant {
        TokenPricing storage pricing = tokenPrices[tokenType];
        require(pricing.basePrice != 0, "Invalid token type");
        _updateDynamicPrice(tokenType);

        uint256 totalCost = pricing.currentPrice * amount;
        require(msg.value >= totalCost, "Insufficient payment");

        MarketMetrics storage metrics = marketMetrics[tokenType];
        metrics.purchasesLast24h += amount;
        metrics.userPurchases[msg.sender] += amount;
        metrics.lastUpdateTime = block.timestamp;

        userTokenBalances[msg.sender][tokenType] += amount;
        emit TokenPurchased(msg.sender, tokenType, amount, pricing.currentPrice);

        // Refund excess if any
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    // Reroll aura for a given token
    function rerollAura(uint256 tokenId) external nonReentrant onlyTokenOwner(tokenId) {
        require(userTokenBalances[msg.sender][TokenType.AuraReroll] > 0, "No reroll tokens");

        userTokenBalances[msg.sender][TokenType.AuraReroll]--;

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            1
        );

        pendingRerolls[requestId] = PendingReroll({
            user: msg.sender,
            tokenId: tokenId,
            attributeToReroll: "AURA_TYPE"
        });

        emit TokenUsed(msg.sender, TokenType.AuraReroll, tokenId);
    }

    // Use an item drop token
    function useItemDrop(uint256 tokenId) external nonReentrant onlyTokenOwner(tokenId) {
        require(userTokenBalances[msg.sender][TokenType.ItemDrop] > 0, "No item drop tokens");

        userTokenBalances[msg.sender][TokenType.ItemDrop]--;

        uint256 requestId = COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            1
        );

        pendingDrops[bytes32(requestId)] = DropData({
            tokenId: tokenId,
            dropType: TokenType.ItemDrop
        });

        emit TokenUsed(msg.sender, TokenType.ItemDrop, tokenId);
    }

    function getTokenBalance(address user, TokenType tokenType) external view returns (uint256) {
        return userTokenBalances[user][tokenType];
    }

    function getCurrentPrice(TokenType tokenType) external view returns (uint256) {
        return tokenPrices[tokenType].currentPrice;
    }

    // Adjust dynamic token price
    function _updateDynamicPrice(TokenType tokenType) internal {
        TokenPricing storage pricing = tokenPrices[tokenType];
        MarketMetrics storage metrics = marketMetrics[tokenType];

        // reset purchases after 24h
        if (block.timestamp >= metrics.lastUpdateTime + 1 days) {
            metrics.purchasesLast24h = 0;
            metrics.lastUpdateTime = block.timestamp;
        }

        uint256 timeSinceLastPurchase = block.timestamp - pricing.lastPurchaseTime;
        uint256 purchaseRate = 0;
        if (block.timestamp > metrics.lastUpdateTime) {
            purchaseRate = (metrics.purchasesLast24h * 1 days) /
                           (block.timestamp - metrics.lastUpdateTime);
        }

        // Example logic
        if (purchaseRate > 100) {
            pricing.currentPrice = (pricing.currentPrice * 110) / 100;
        } else if (timeSinceLastPurchase > 12 hours) {
            pricing.currentPrice = (pricing.currentPrice * 95) / 100;
        }

        if (pricing.currentPrice > pricing.maxPrice) {
            pricing.currentPrice = pricing.maxPrice;
        } else if (pricing.currentPrice < pricing.minPrice) {
            pricing.currentPrice = pricing.minPrice;
        }

        pricing.lastPurchaseTime = block.timestamp;
        emit PriceUpdated(tokenType, pricing.currentPrice);
    }

    /* ============ Chainlink VRF Fulfill ============ */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 randomness = randomWords[0];

        // 1) If it's a reroll
        if (pendingRerolls[requestId].user != address(0)) {
            _finalizeReroll(requestId, randomness);
        }
        // 2) If it's an item drop
        else if (pendingDrops[bytes32(requestId)].tokenId != 0) {
            _finalizeDrop(bytes32(requestId), randomness);
        }
        // else unknown request
    }

    function _finalizeReroll(uint256 requestId, uint256 randomness) internal {
        PendingReroll memory data = pendingRerolls[requestId];
        require(data.user != address(0), "Invalid reroll");

        uint256 tokenId = data.tokenId;
        AuraRarity oldRarity = beeAuras[tokenId].rarity;
        AuraEffect memory newAura = _generateAuraEffect(randomness);

        // Example logic: keep the higher rarity
        if (uint256(newAura.rarity) < uint256(oldRarity)) {
            newAura.rarity = oldRarity;
        }
        beeAuras[tokenId] = newAura;

        emit AuraRerolled(tokenId, oldRarity, newAura.rarity);
        delete pendingRerolls[requestId];
    }

    function _finalizeDrop(bytes32 requestId, uint256 randomness) internal {
        DropData memory data = pendingDrops[requestId];
        require(data.tokenId != 0, "Invalid drop request");

        uint256 tokenId = data.tokenId;
        uint256 itemId = _generateRandomItem(tokenId, randomness);
        Item storage newItem = beeHoney[tokenId].items[itemId];

        emit ItemDropped(tokenId, itemId, newItem.rarity);
        delete pendingDrops[requestId];
    }

    /* ============ Utility to add Mythic Combos ============ */

    /* ============ Fallback & Receive ============ */
    receive() external payable {}
    fallback() external payable {}
}
