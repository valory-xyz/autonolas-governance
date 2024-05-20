// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {VerifyBridgedData} from "./VerifyBridgedData.sol";

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Provided wrong function selector.
/// @param functionSig Function selector.
/// @param chainId Chain Id.
error WrongSelector(bytes4 functionSig, uint256 chainId);

/// @dev Provided wrong L2 bridge mediator address.
/// @param provided Provided address.
/// @param expected Expected address.
error WrongL2BridgeMediator(address provided, address expected);

/// @title ProcessBridgedDataOptimism - Smart contract for verifying the Guard CM bridged data on Optimism and Base
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataOptimism is VerifyBridgedData {
    // sendMessage selector in bridge mediator L1
    bytes4 public constant SEND_MESSAGE = bytes4(keccak256(bytes("sendMessage(address,bytes,uint32)")));
    // processMessageFromSource selector (Optimism and Base chains)
    bytes4 public constant PROCESS_MESSAGE_FROM_SOURCE = bytes4(keccak256(bytes("processMessageFromSource(bytes)")));
    // Minimum payload length for message on Optimism accounting for all required encoding and at least one selector
    uint256 public constant MIN_OPTIMISM_PAYLOAD_LENGTH = 292;

    /// @dev Processes bridged data: checks the header and verifies the payload.
    /// @param data Full data bytes with the header.
    /// @param bridgeMediatorL2 Address of a bridged mediator on L2.
    /// @param chainId L2 chain Id.
    function processBridgeData(
        bytes memory data,
        address bridgeMediatorL2,
        uint256 chainId
    ) external override
    {
        // Check the L1 initial selector
        bytes4 functionSig = bytes4(data);
        if (functionSig != SEND_MESSAGE) {
            revert WrongSelector(functionSig, chainId);
        }

        // Check if the data length is less than a size of a selector plus the message minimum payload size
        if (data.length < MIN_OPTIMISM_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(data.length, MIN_OPTIMISM_PAYLOAD_LENGTH);
        }

        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Decode the sendMessage payload: optimismMessenger (L2), mediatorPayload (needs decoding), minGasLimit
        (address optimismMessenger, bytes memory mediatorPayload, ) = abi.decode(payload, (address, bytes, uint32));
        // Check that the optimism messenger matches the L2 bridge mediator address
        if (optimismMessenger != bridgeMediatorL2) {
            revert WrongL2BridgeMediator(optimismMessenger, bridgeMediatorL2);
        }

        // Check the L2 initial selector
        functionSig = bytes4(mediatorPayload);
        if (functionSig != PROCESS_MESSAGE_FROM_SOURCE) {
            revert WrongSelector(functionSig, chainId);
        }

        // Copy the data without a selector
        bytes memory bridgePayload = new bytes(mediatorPayload.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < bridgePayload.length; ++i) {
            bridgePayload[i] = mediatorPayload[i + SELECTOR_DATA_LENGTH];
        }

        // Decode the processMessageFromSource payload: l2Message (executed on L2)
        (bytes memory l2Message) = abi.decode(bridgePayload, (bytes));

        // Verify processMessageFromSource payload
        _verifyBridgedData(l2Message, chainId);
    }
}