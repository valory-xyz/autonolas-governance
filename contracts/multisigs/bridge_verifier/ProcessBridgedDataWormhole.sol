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

/// @title ProcessBridgedDataWormhole - Smart contract for verifying the Guard CM bridged data on L2 via Wormhole standard
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataWormhole is VerifyBridgedData {
    // sendPayloadToEvm selector in bridge mediator L1 with the possibility of refund for reverted calls
    bytes4 public constant SEND_MESSAGE_REFUND = bytes4(keccak256(bytes("sendPayloadToEvm(uint16,address,bytes,uint256,uint256,uint16,address)")));
    // sendPayloadToEvm selector in bridge mediator L1
    bytes4 public constant SEND_MESSAGE = bytes4(keccak256(bytes("sendPayloadToEvm(uint16,address,bytes,uint256,uint256)")));
    // Minimum payload length for message sent via Wormhole accounting for all required encoding and at least one selector
    uint256 public constant MIN_WORMHOLE_PAYLOAD_LENGTH = 324;

    /// @dev Processes bridged data: checks the header and verifies the payload.
    /// @notice It is out of scope of the verification procedure to check if the Wormhole format chain Id corresponding
    ///         to the original EVM chain Id is correctly setup during the bridge call.
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
        if (functionSig != SEND_MESSAGE && functionSig != SEND_MESSAGE_REFUND) {
            revert WrongSelector(functionSig, chainId);
        }

        // Check if the data length is less than a size of a selector plus the message minimum payload size
        if (data.length < MIN_WORMHOLE_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(data.length, MIN_WORMHOLE_PAYLOAD_LENGTH);
        }

        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Decode the payload depending on the selector
        address wormholeMessenger;
        bytes memory l2Message;
        if (functionSig == SEND_MESSAGE) {
            (, wormholeMessenger, l2Message, , ) =
                abi.decode(payload, (uint16, address, bytes, uint256, uint256));
        } else {
            (, wormholeMessenger, l2Message, , , , ) =
                abi.decode(payload, (uint16, address, bytes, uint256, uint256, uint16, address));
        }

        // Check that the wormhole messenger matches the L2 bridge mediator address
        if (wormholeMessenger != bridgeMediatorL2) {
            revert WrongL2BridgeMediator(wormholeMessenger, bridgeMediatorL2);
        }

        // Verify processMessageFromSource payload
        _verifyBridgedData(l2Message, chainId);
    }
}