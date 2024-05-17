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

/// @title ProcessBridgedDataPolygon - Smart contract for verifying the Guard CM bridged data on Polygon
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataPolygon is VerifyBridgedData {
    // sendMessageToChild selector in bridge mediator L1
    bytes4 public constant SEND_MESSAGE_TO_CHILD = bytes4(keccak256(bytes("sendMessageToChild(address,bytes)")));
    // Minimum payload length for message on Polygon accounting for all required encoding and at least one selector
    uint256 public constant MIN_POLYGON_PAYLOAD_LENGTH = 164;

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
        if (functionSig != SEND_MESSAGE_TO_CHILD) {
            revert WrongSelector(functionSig, chainId);
        }

        // Check if the data length is less than a size of a selector plus the message minimum payload size
        if (data.length < MIN_POLYGON_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(data.length, MIN_POLYGON_PAYLOAD_LENGTH);
        }

        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + SELECTOR_DATA_LENGTH];
        }

        // Decode sendMessageToChild payload: fxGovernorTunnel (L2), l2Message (executed on L2)
        (address fxGovernorTunnel, bytes memory l2Message) = abi.decode(payload, (address, bytes));
        // Check that the fxGovernorTunnel matches the L2 bridge mediator address
        if (fxGovernorTunnel != bridgeMediatorL2) {
            revert WrongL2BridgeMediator(fxGovernorTunnel, bridgeMediatorL2);
        }

        // Verify sendMessageToChild payload
        _verifyBridgedData(l2Message, chainId);
    }
}