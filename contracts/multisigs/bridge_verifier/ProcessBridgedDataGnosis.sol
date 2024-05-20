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

/// @title ProcessBridgedDataGnosis - Smart contract for verifying the Guard CM bridged data on Gnosis
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ProcessBridgedDataGnosis is VerifyBridgedData {
    // requireToPassMessage selector in bridge mediator L1
    bytes4 public constant REQUIRE_TO_PASS_MESSAGE = bytes4(keccak256(bytes("requireToPassMessage(address,bytes,uint256)")));
    // processMessageFromForeign selector (Gnosis chain)
    bytes4 public constant PROCESS_MESSAGE_FROM_FOREIGN = bytes4(keccak256(bytes("processMessageFromForeign(bytes)")));
    // Minimum payload length for message on Gnosis accounting for all required encoding and at least one selector
    uint256 public constant MIN_GNOSIS_PAYLOAD_LENGTH = 292;

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
        if (functionSig != REQUIRE_TO_PASS_MESSAGE) {
            revert WrongSelector(functionSig, chainId);
        }

        // Check if the data length is less than a size of a selector plus the message minimum payload size
        if (data.length < MIN_GNOSIS_PAYLOAD_LENGTH) {
            revert IncorrectDataLength(data.length, MIN_GNOSIS_PAYLOAD_LENGTH);
        }

        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Decode the requireToPassMessage payload: homeMediator (L2), mediatorPayload (needs decoding), requestGasLimit
        (address homeMediator, bytes memory mediatorPayload, ) = abi.decode(payload, (address, bytes, uint256));
        // Check that the home mediator matches the L2 bridge mediator address
        if (homeMediator != bridgeMediatorL2) {
            revert WrongL2BridgeMediator(homeMediator, bridgeMediatorL2);
        }

        // Check the L2 initial selector
        functionSig = bytes4(mediatorPayload);
        if (functionSig != PROCESS_MESSAGE_FROM_FOREIGN) {
            revert WrongSelector(functionSig, chainId);
        }

        // Copy the data without a selector
        bytes memory bridgePayload = new bytes(mediatorPayload.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < bridgePayload.length; ++i) {
            bridgePayload[i] = mediatorPayload[i + SELECTOR_DATA_LENGTH];
        }

        // Decode the processMessageFromForeign payload: l2Message (executed on L2)
        (bytes memory l2Message) = abi.decode(bridgePayload, (bytes));

        // Verify processMessageFromForeign payload
        _verifyBridgedData(l2Message, chainId);
    }
}