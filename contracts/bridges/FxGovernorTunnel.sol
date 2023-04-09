// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// IFxMessageProcessor represents interface to process message
interface IFxMessageProcessor {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external;
}

/// @dev Only `fxChild` is allowed to call the function.
/// @param sender Sender address.
/// @param fxChild Required Fx Child address.
error FxChildOnly(address sender, address fxChild);

/// @dev Only on behalf of `rootGovernor` the function is allowed to process the data.
/// @param sender Sender address.
/// @param rootGovernor Required Root Governor address.
error RootGovernorOnly(address sender, address rootGovernor);

/// @title FxGovernorTunnel - Smart contract for the governor child tunnel bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract FxGovernorTunnel is IFxMessageProcessor {
    event MessageReceived(uint256 indexed stateId, address indexed rootMessageSender, bytes data);

    // FX child address
    address public immutable fxChild;
    // Root governor address
    address public immutable rootGovernor;

    constructor(address _fxChild, address _rootGovernor) {
        fxChild = _fxChild;
        rootGovernor = _rootGovernor;
    }

    /// @dev Process message received from the Root Tunnel.
    /// @notice This is called by onStateReceive function. Since it is called via a system call,
    ///         any event will not be emitted during its execution.
    /// @notice Packing mechanism is inspired by the Safe Ecosystem MultiSend contract:
    ///         https://github.com/safe-global/safe-contracts/blob/v1.3.0/contracts/libraries/MultiSendCallOnly.sol
    /// @param stateId Unique state id.
    /// @param rootMessageSender Root message sender.
    /// @param data Bytes message sent from the Root Tunnel.
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external override {
        // Check for the Fx Child address
        if(msg.sender != fxChild) {
            revert FxChildOnly(msg.sender, fxChild);
        }

        // Check for the Root Governor address
        if(rootMessageSender != rootGovernor) {
            revert RootGovernorOnly(rootMessageSender, rootGovernor);
        }

        // Emit received message for testing
        emit MessageReceived(stateId, rootMessageSender, data);
        
        // Unpack and process the data
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let length := mload(data)
            let i := 0x20
            // While loop until the data length is reached
            for {} lt(i, length) {} {
                // First 20 bytes is the address
                let to := mload(add(data, i))
                // Offset the data by 20 bytes of the to address
                let value := mload(add(data, add(i, 0x14)))
                // Offset the data by 32 bytes (20 address bytes + 12 value bytes)
                let payloadLength := mload(add(data, add(i, 0x20)))
                // Offset the data by 36 bytes (20 address bytes + 12 value bytes + 4 payload length bytes)
                let payload := add(data, add(i, 0x24))
                let success := call(gas(), to, value, payload, payloadLength, 0, 0)
                if eq(success, 0) {
                    revert(0, 0)
                }
                // Next transaction starts at 36 bytes + payload length
                i := add(i, add(0x24, payloadLength))
            }
        }
    }
}