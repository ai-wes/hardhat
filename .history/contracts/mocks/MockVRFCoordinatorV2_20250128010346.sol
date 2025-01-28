// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @notice A mock VRFCoordinator for local testing of VRFConsumerBaseV2-based contracts.
 *         It tracks request IDs and simulates fulfilling random words.
 */
contract MockVRFCoordinatorV2 {
    uint256 private _nextRequestId;
    // Optionally track each request data
    struct VRFRequest {
        address caller;
        uint64 subId;
        uint16 minConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
    }

    mapping(uint256 => VRFRequest) public requests;
    uint256 public lastRequestId; // public read

    // For demonstration only. In real scenarios, your VRF consumer must trust that
    // only the real VRF coordinator can call fulfillRandomWords.

    /**
     * @notice Called by the VRF consumer contract to request random words.
     * @param keyHash        dummy param to match VRFConsumerBaseV2 interface
     * @param subId          subscription ID
     * @param minConf        minimum confirmations
     * @param gasLimit       callback gas limit
     * @param numWords       how many random words to return
     * @return requestId     incremented requestId for the test environment
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minConf,
        uint32 gasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        _nextRequestId++;
        requestId = _nextRequestId;
        lastRequestId = requestId;

        requests[requestId] = VRFRequest({
            caller: msg.sender,
            subId: subId,
            minConfirmations: minConf,
            callbackGasLimit: gasLimit,
            numWords: numWords
        });
    }

    /**
     * @notice Mock function to fulfill random words to the consumer. 
     *         In production, only the Chainlink VRF coordinator would do this.
     * @param _requestId     which request to fulfill
     * @param _randomWords   array of random words
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) external {
        VRFRequest memory req = requests[_requestId];
        require(req.caller != address(0), "Invalid requestId");

        // The VRF consumer must have a method rawFulfillRandomWords(uint256, uint256[])
        // If you're using VRFConsumerBaseV2, that function is internal but can be invoked like below:
        (bool success, ) = req.caller.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                _requestId,
                _randomWords
            )
        );
        require(success, "fulfillRandomWords: Consumer call failed");
    }
}
