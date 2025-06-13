// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

error ExecFailed(address relayer, bytes payload);

/// @title MockTimelock - Mock of Timelock contract on the L1 side
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelock {
    event FundsReceived(uint256 value);

    // Relayer address on L1
    address public immutable relayer;

    constructor(address _relayer) {
        relayer = _relayer;
    }

    /// @dev Executes the payload with the relayer address.
    /// @param payload Bytes of payload.
    function execute(bytes memory payload) external payable {
        (bool success, ) = relayer.call{value: msg.value}(payload);
        if (!success) {
            revert ExecFailed(relayer, payload);
        }
    }

    /// @dev Executes the payload with the arbitrary specified address.
    /// @param customRelayer Custom relayer address.
    /// @param payload Bytes of payload.
    function executeCustomRelayer(address customRelayer, bytes memory payload) external payable {
        (bool success, ) = customRelayer.call{value: msg.value}(payload);
        if (!success) {
            revert ExecFailed(customRelayer, payload);
        }
    }

    receive() external payable {
        emit FundsReceived(msg.value);
    }
}