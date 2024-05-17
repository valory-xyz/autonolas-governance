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

/// @title ProcessBridgedDataArbitrum - Smart contract for verifying the Guard CM bridged data on Arbitrum
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataArbitrum is VerifyBridgedData {
    // unsafeCreateRetryableTicket selector in bridge mediator L1
    bytes4 public constant CREATE_TICKET_UNSAFE = bytes4(keccak256(bytes("unsafeCreateRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)")));
    // createRetryableTicket selector in bridge mediator L1
    bytes4 public constant CREATE_TICKET = bytes4(keccak256(bytes("createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)")));
    // Minimum payload length for message on Arbitrum accounting for all required encoding and at least one selector
    uint256 public constant MIN_ARBITRUM_PAYLOAD_LENGTH = 324;

    /// @dev Processes bridged data: checks the header and verifies the payload.
    /// @param data Full data bytes with the header.
    /// @param chainId L2 chain Id.
    function processBridgeData(
        bytes memory data,
        address,
        uint256 chainId
    ) external override
    {
        // Check the L1 initial selector
        bytes4 functionSig = bytes4(data);
        if (functionSig != CREATE_TICKET_UNSAFE && functionSig != CREATE_TICKET) {
            revert WrongSelector(functionSig, chainId);
        }

        // Check if the data length is less than a size of a selector plus the message minimum payload size
        if (data.length < MIN_ARBITRUM_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(data.length, MIN_ARBITRUM_PAYLOAD_LENGTH);
        }

        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Decode the payload depending on the selector
        (address targetAddress, , , , , , , bytes memory targetPayload) =
            abi.decode(payload, (address, uint256, uint256, address, address, uint256, uint256, bytes));

        // Verify the scope of the data
        _verifyData(targetAddress, targetPayload, chainId);
    }
}