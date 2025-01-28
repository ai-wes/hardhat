// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockVRFCoordinatorV2
 * @dev A minimal mock of Chainlink's VRFCoordinatorV2Interface for local testing.
 *      This mock allows requesting random words and then manually triggering the callback
 *      to simulate Chainlink fulfilling randomness requests.
 */
contract MockVRFCoordinatorV2 {
    uint64 private s_currentSubId;
    uint256 private s_currentRequestId;
    mapping(uint64 => address) private s_subscriptionOwners;
    mapping(uint256 => address) private s_consumers;

    event RandomWordsRequested(uint256 indexed requestId, address indexed sender);
    event SubscriptionCreated(uint64 subId, address owner);
    event RandomWordsFulfilled(uint256 indexed requestId, address indexed caller);

    constructor() {
        // Just initialize a dummy subscription
        s_currentSubId = 1;
        s_subscriptionOwners[s_currentSubId] = msg.sender;
        emit SubscriptionCreated(s_currentSubId, msg.sender);
    }

    /**
     * @notice Simulate the requestRandomWords function from VRFCoordinatorV2Interface.
     */
    function requestRandomWords(
        bytes32, /* keyHash */
        uint64,  /* subId */
        uint16,  /* minimumRequestConfirmations */
        uint32,  /* callbackGasLimit */
        uint32   /* numWords */
    ) external returns (uint256) {
        s_currentRequestId++;
        s_consumers[s_currentRequestId] = msg.sender;
        emit RandomWordsRequested(s_currentRequestId, msg.sender);
        return s_currentRequestId;
    }

    /**
     * @notice Simulate fulfilling the randomness request by calling back into the requesting contract.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        address consumer = s_consumers[requestId];
        require(consumer != address(0), "Invalid requestId");
        // Callback to the consumer
        // In real Chainlink, the function is `rawFulfillRandomWords`, but your contract expects `fulfillRandomWords`.
        // We'll assume a standard signature: fulfillRandomWords(uint256, uint256[]).
        (bool success, ) = consumer.call(
            abi.encodeWithSignature("fulfillRandomWords(uint256,uint256[])", requestId, randomWords)
        );
        require(success, "Callback failed");
        emit RandomWordsFulfilled(requestId, msg.sender);
    }

    /**
     * @notice Returns a dummy subscription ID for local usage. 
     */
    function createSubscription() external returns (uint64) {
        return s_currentSubId;
    }
}
