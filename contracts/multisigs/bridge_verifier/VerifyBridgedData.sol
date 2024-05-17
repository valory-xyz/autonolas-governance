// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {VerifyData} from "../VerifyData.sol";

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error DataLengthIncorrect(uint256 expected, uint256 provided);

/// @title VerifyBridgedData - Smart contract for verifying the Guard CM bridged data
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract VerifyBridgedData is VerifyData {
    // Minimum data length that contains at least a selector (4 bytes or 32 bits)
    uint256 public constant SELECTOR_DATA_LENGTH = 4;

    /// @dev Processes bridged data: checks the header and verifies the payload.
    /// @param data Full data bytes with the header.
    /// @param bridgeMediatorL2 Address of a bridged mediator on L2.
    /// @param chainId L2 chain Id.
    function processBridgeData(
        bytes memory data,
        address bridgeMediatorL2,
        uint256 chainId
    ) external virtual;

    /// @dev Verifies the bridged data for authorized combinations of targets and selectors.
    /// @notice The processed data is packed as a set of bytes that are assembled using the following parameters:
    ///         address target, uint96 value, uint32 payloadLength, bytes payload.
    /// @param data Payload bytes.
    /// @param chainId L2 chain Id.
    function _verifyBridgedData(bytes memory data, uint256 chainId) internal {
        // Unpack and process the data
        // We need to skip first 12 bytes as those are zeros from encoding
        for (uint256 i = 0; i < data.length;) {
            address target;
            uint32 payloadLength;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // First 20 bytes is the address (160 bits)
                i := add(i, 20)
                target := mload(add(data, i))
                // Offset the data by 12 bytes of value (96 bits) and by 4 bytes of payload length (32 bits)
                i := add(i, 16)
                payloadLength := mload(add(data, i))
            }

            // Check for the zero address
            if (target == address(0)) {
                revert ZeroAddress();
            }

            // The payload length must be at least of the a function selector size
            if (payloadLength < SELECTOR_DATA_LENGTH) {
                revert DataLengthIncorrect(payloadLength, SELECTOR_DATA_LENGTH);
            }

            // Get the payload
            bytes memory payload = new bytes(payloadLength);
            for (uint256 j = 0; j < payloadLength; ++j) {
                payload[j] = data[i + j];
            }
            // Offset the data by the payload number of bytes
            i += payloadLength;

            // Verify the scope of the data
            _verifyData(target, payload, chainId);
        }
    }
}