// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title WormholeL1Receiver - Smart contract for the L1 message receiving via wormhole
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeL1Receiver {
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    /// @dev Processes a message received from L1 Wormhole Relayer contract.
    /// @notice The sender must be the source contract address.
    /// @param data Bytes message sent from L1 Wormhole Relayer contract.
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
        // Emit received message
        emit MessageReceived(sourceAddress, data, deliveryHash, sourceChain);
    }
}