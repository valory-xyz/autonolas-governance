// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IBridgeErrors} from "../../interfaces/IBridgeErrors.sol";

interface IWormhole {
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

/// @title WormholeL1Sender - Smart contract for sending a message from L2 to L1 via wormhole
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeL1Sender is IBridgeErrors {
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    uint256 public constant GAS_LIMIT = 50_000;
    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source chain Id
    uint16 public immutable sourceChainId;
    // Source contract to communicate with on L1
    address public sourceSender;

    /// @dev WormholeMessenger constructor.
    /// @param _wormholeRelayer L2 Wormhole Relayer address.
    /// @param _sourceChainId Source wormhole format chain Id.
    constructor(address _wormholeRelayer,  uint16 _sourceChainId, address _sourceSender) {
        // Check for zero addresses
        if (_wormholeRelayer == address(0) || _sourceSender == address(0)) {
            revert ZeroAddress();
        }

        // Check source chain Id
        if (_sourceChainId == 0) {
            revert ZeroValue();
        }

        wormholeRelayer = _wormholeRelayer;
        sourceChainId = _sourceChainId;
        sourceSender = _sourceSender;
    }

    function sendMessage() external payable {
        bytes32 message = keccak256(abi.encode("Hello"));

        // Send the message
        IWormhole(wormholeRelayer).sendPayloadToEvm{value: msg.value}(
            sourceChainId,
            sourceSender,
            abi.encode(message),
            0,
            GAS_LIMIT
        );
    }

    receive() external payable {}
}