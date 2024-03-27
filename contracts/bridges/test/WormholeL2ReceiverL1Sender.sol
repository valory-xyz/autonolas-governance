// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IBridgeErrors} from "../../interfaces/IBridgeErrors.sol";

interface IWormhole {
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    function sendPayloadToEvm(
        // Chain ID in Wormhole format
        uint16 targetChain,
        // Contract Address on target chain we're sending a message to
        address targetAddress,
        // The payload, encoded as bytes
        bytes memory payload,
        // How much value to attach to the delivery transaction
        uint256 receiverValue,
        // The gas limit to set on the delivery transaction
        uint256 gasLimit
    ) external payable returns (
        // Unique, incrementing ID, used to identify a message
        uint64 sequence
    );
}

/// @title WormholeL2ReceiverL1Sender - Smart contract for the L1-L2-L1 message relaying via wormhole
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeL2ReceiverL1Sender is IBridgeErrors {
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    uint256 public constant GAS_LIMIT = 50_000;
    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source chain Id
    uint16 public immutable sourceChainId;
    // Source contract to communicate with on L1
    address public sourceSender;
    // Delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeMessenger constructor.
    /// @param _wormholeRelayer L2 Wormhole Relayer address.
    /// @param _sourceChainId Source wormhole format chain Id.
    constructor(address _wormholeRelayer,  uint16 _sourceChainId) {
        // Check for zero addresses
        if (_wormholeRelayer == address(0)) {
            revert ZeroAddress();
        }

        // Check source chain Id
        if (_sourceChainId == 0) {
            revert ZeroValue();
        }

        wormholeRelayer = _wormholeRelayer;
        sourceChainId = _sourceChainId;
    }


    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source contract address.
    /// @param data Bytes message sent from L2 Wormhole Relayer contract.
    /// @param sourceAddress The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChain The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        // Check L2 Wormhole Relayer address
        if (msg.sender != wormholeRelayer) {
            revert TargetRelayerOnly(msg.sender, wormholeRelayer);
        }

        // Check the source chain Id
        if (sourceChain != sourceChainId) {
            revert WrongSourceChainId(sourceChain, sourceChainId);
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        sourceSender = abi.decode(data, (address));

        // Get a quote for the cost of gas for delivery
        uint256 cost;
        (cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(sourceChain, 0, GAS_LIMIT);

        // Send the message
        IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(
            sourceChain,
            sourceSender,
            abi.encode(keccak256("Hello")),
            0,
            GAS_LIMIT
        );

        // Emit received message
        emit MessageReceived(sourceAddress, data, deliveryHash, sourceChain);
    }

    receive() external payable {}
}