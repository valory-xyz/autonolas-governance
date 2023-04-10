// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// IFxMessageProcessor represents interface to process message
interface IFxMessageProcessor {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Only self contract is allowed to call the function.
/// @param sender Sender address.
/// @param instance Required contract instance address.
error SelfCallOnly(address sender, address instance);

/// @dev Only `fxChild` is allowed to call the function.
/// @param sender Sender address.
/// @param fxChild Required Fx Child address.
error FxChildOnly(address sender, address fxChild);

/// @dev Only on behalf of `rootGovernor` the function is allowed to process the data.
/// @param sender Sender address.
/// @param rootGovernor Required Root Governor address.
error RootGovernorOnly(address sender, address rootGovernor);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Target execution failed.
/// @param target Target address.
/// @param value Provided value.
/// @param payload Provided payload.
error TargetExecFailed(address target, uint256 value, bytes payload);

/// @title FxGovernorTunnel - Smart contract for the governor child tunnel bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract FxGovernorTunnel is IFxMessageProcessor {
    event MessageReceived(uint256 indexed stateId, address indexed rootMessageSender, bytes data);

    // Default payload data length includes the number of bytes of at least one address (20 bytes or 160 bits),
    // value (12 bytes or 96 bits) and the payload size (4 bytes or 32 bits)
    uint256 public constant DEFAULT_DATA_LENGTH = 36;
    // FX child address
    address public immutable fxChild;
    // Root governor address
    address public rootGovernor;

    /// @dev FxGovernorTunnel constructor.
    /// @param _fxChild Fx Child address.
    /// @param _rootGovernor Root Governor address.
    constructor(address _fxChild, address _rootGovernor) {
        // Check fo zero addresses
        if (_fxChild == address(0) || _rootGovernor == address(0)) {
            revert ZeroAddress();
        }

        fxChild = _fxChild;
        rootGovernor = _rootGovernor;
    }

    function changeRootGovernor(address newRootGovernor) external {
        // Check if the change is authorized by the previous governor itself
        // This is possible only if all the checks in the message process function pass and the contract calls itself
        if (msg.sender != address(this)) {
            revert SelfCallOnly(msg.sender, address(this));
        }

        // Check for the zero address
        if (newRootGovernor == address(0)) {
            revert ZeroAddress();
        }

        rootGovernor = newRootGovernor;
    }

    /// @dev Process message received from the Root Tunnel.
    /// @notice This is called by onStateReceive function. The sender must be the Root Governor address (Timelock).
    /// @param stateId Unique state id.
    /// @param rootMessageSender Root message sender.
    /// @param data Bytes message sent from the Root Tunnel. The data must be encoded as a set of continuous
    ///        transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits)
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block
    ///        - payload as bytes, with the length equal to the specified payload length
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external override {
        // Check for the Fx Child address
        if(msg.sender != fxChild) {
            revert FxChildOnly(msg.sender, fxChild);
        }

        // Check for the Root Governor address
        if(rootMessageSender != rootGovernor) {
            revert RootGovernorOnly(rootMessageSender, rootGovernor);
        }

        // Check for the correct data length
        uint256 dataLength = data.length;
        if (dataLength < DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
        }
        
        // Unpack and process the data
        for (uint256 i = 0; i < dataLength;) {
            address target;
            uint96 value;
            uint32 payloadLength;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // First 20 bytes is the address (160 bits)
                i := add(i, 20)
                target := mload(add(data, i))
                // Offset the data by 12 bytes of value (96 bits)
                i := add(i, 12)
                value := mload(add(data, i))
                // Offset the data by 4 bytes of payload length (32 bits)
                i := add(i, 4)
                payloadLength := mload(add(data, i))
            }

            // Get the payload
            bytes memory payload = new bytes(payloadLength);
            for (uint256 j = 0; j < payloadLength; ++j) {
                payload[j] = data[i + j];
            }
            // Offset the data by the payload number of bytes
            i += payloadLength;

            // Call the target with the provided payload
            (bool success, ) = target.call{value: value}(payload);
            if (!success) {
                revert TargetExecFailed(target, value, payload);
            }
        }

        // Emit received message
        emit MessageReceived(stateId, rootMessageSender, data);
    }
}