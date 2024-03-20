// Sources flattened with hardhat v2.20.1 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev The combination of target and selector is not authorized.
/// @param target Target address.
/// @param selector Function selector.
/// @param chainId Chain Id.
error NotAuthorized(address target, bytes4 selector, uint256 chainId);

/// @title VerifyData - Smart contract for verifying the Guard CM data
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract VerifyData {
    // Mapping of (target address | bytes4 selector | uint64 chain Id) => enabled / disabled
    mapping(uint256 => bool) public mapAllowedTargetSelectorChainIds;

    /// @dev Verifies authorized combinations of target and selector.
    /// @notice The bottom-most internal function is still not "view" since some reverts are not explicitly handled
    /// @param target Target address.
    /// @param data Payload bytes.
    /// @param chainId Chain Id.
    function _verifyData(address target, bytes memory data, uint256 chainId) internal {
        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetSelectorChainId = uint256(uint160(target));
        // selector occupies next 32 bits
        targetSelectorChainId |= uint256(uint32(bytes4(data))) << 160;
        // chainId occupies next 64 bits
        targetSelectorChainId |= chainId << 192;

        // Check the authorized combination of target and selector
        if (!mapAllowedTargetSelectorChainIds[targetSelectorChainId]) {
            revert NotAuthorized(target, bytes4(data), chainId);
        }
    }
}


// File contracts/multisigs/bridge_verifier/VerifyBridgedData.sol
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

/// @title ProcessBridgedDataArbitrum - Smart contract for verifying the Guard CM bridged data on Arbitrum
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataArbitrum is VerifyBridgedData {
    // unsafeCreateRetryableTicket selector in bridge mediator L1
    bytes4 public constant CREATE_TICKET_UNSAFE = bytes4(keccak256(bytes("unsafeCreateRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,uint256,bytes)")));
    // createRetryableTicket selector in bridge mediator L1
    bytes4 public constant CREATE_TICKET = bytes4(keccak256(bytes("createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,uint256,bytes)")));
    // Minimum payload length for message on Arbitrum accounting for all required encoding and at least one selector
    uint256 public constant MIN_ARBITRUM_PAYLOAD_LENGTH = 584;

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
        (address targetAddress, , , , , , , , bytes memory targetPayload) =
            abi.decode(payload, (address, uint256, uint256, address, address, uint256, uint256, uint256, bytes));

        // Verify the scope of the data
        _verifyData(targetAddress, targetPayload, chainId);
    }
}
