// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Bridge errors.
interface IBridgeErrors {
    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Provided zero value.
    error ZeroValue();

    /// @dev Only self contract is allowed to call the function.
    /// @param sender Sender address.
    /// @param instance Required contract instance address.
    error SelfCallOnly(address sender, address instance);

    /// @dev Only L2 relayer is allowed to call the function.
    /// @param sender Sender address.
    /// @param targetRelayer Required L2 relayer address.
    error TargetRelayerOnly(address sender, address targetRelayer);

    /// @dev Wrong source chain Id.
    /// @param received Chain Id received.
    /// @param required Required chain Id.
    error WrongSourceChainId(uint256 received, uint256 required);

    /// @dev Only on behalf of `sourceGovernor` the function is allowed to process the data.
    /// @param sender Sender address.
    /// @param sourceGovernor Required source governor address.
    error SourceGovernorOnly(address sender, address sourceGovernor);

    /// @dev Only on behalf of `sourceGovernor` the function is allowed to process the data.
    /// @param sender Sender address.
    /// @param sourceGovernor Required source governor address.
    error SourceGovernorOnly32(bytes32 sender, bytes32 sourceGovernor);

    /// @dev The message with a specified hash has already been delivered.
    /// @param deliveryHash Delivery hash.
    error AlreadyDelivered(bytes32 deliveryHash);

    /// @dev Provided incorrect data length.
    /// @param expected Expected minimum data length.
    /// @param provided Provided data length.
    error IncorrectDataLength(uint256 expected, uint256 provided);

    /// @dev Provided value is bigger than the actual balance.
    /// @param value Provided value.
    /// @param balance Actual balance.
    error InsufficientBalance(uint256 value, uint256 balance);

    /// @dev Target execution failed.
    /// @param target Target address.
    /// @param value Provided value.
    /// @param payload Provided payload.
    error TargetExecFailed(address target, uint256 value, bytes payload);
}
