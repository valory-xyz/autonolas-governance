// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BridgeMessenger} from "./BridgeMessenger.sol";

/// @title WormholeMessenger - Smart contract for the governor bridge communication via wormhole
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeMessenger is BridgeMessenger {
    event SourceGovernorUpdated(bytes32 indexed sourceGovernor);
    event MessageReceived(bytes32 indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source governor chain Id
    uint16 public immutable sourceGovernorChainId;
    // Source governor address on L1 that is authorized to propagate the transaction execution across the bridge
    bytes32 public sourceGovernor;
    // Map of delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeMessenger constructor.
    /// @param _wormholeRelayer L2 Wormhole Relayer address.
    /// @param _sourceGovernor Source governor address (ETH).
    /// @param _sourceGovernorChainId Source governor wormhole format chain Id.
    constructor(address _wormholeRelayer, bytes32 _sourceGovernor, uint16 _sourceGovernorChainId) {
        // Check for zero addresses
        if (_wormholeRelayer == address(0)) {
            revert ZeroAddress();
        }

        // Check source governor chain Id
        if (_sourceGovernor == 0 || _sourceGovernorChainId == 0) {
            revert ZeroValue();
        }

        wormholeRelayer = _wormholeRelayer;
        sourceGovernor = _sourceGovernor;
        sourceGovernorChainId = _sourceGovernorChainId;
    }

    /// @dev Changes the source governor address (original Timelock).
    /// @notice The only way to change the source governor address is by the Timelock on L1 to request that change.
    ///         This triggers a self-contract transaction of BridgeMessenger that changes the source governor address.
    /// @param newSourceGovernor New source governor address.
    function changeSourceGovernor(bytes32 newSourceGovernor) external {
        // Check if the change is authorized by the previous governor itself
        // This is possible only if all the checks in the message process function pass and the contract calls itself
        if (msg.sender != address(this)) {
            revert SelfCallOnly(msg.sender, address(this));
        }

        // Check for the zero address
        if (newSourceGovernor == 0) {
            revert ZeroValue();
        }

        sourceGovernor = newSourceGovernor;
        emit SourceGovernorUpdated(newSourceGovernor);
    }

    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source governor address (Timelock).
    /// @param data Bytes message sent from L2 Wormhole Relayer contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
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
        if (sourceChain != sourceGovernorChainId) {
            revert WrongSourceChainId(sourceChain, sourceGovernorChainId);
        }

        // Check for the source governor address
        bytes32 governor = sourceGovernor;
        if (governor != sourceAddress) {
            revert SourceGovernorOnly32(sourceAddress, governor);
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

        // Process the data
        _processData(data);

        // Emit received message
        emit MessageReceived(governor, data, deliveryHash, sourceChain);
    }
}