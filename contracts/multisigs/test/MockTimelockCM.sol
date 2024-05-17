// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

error ExecFailed(address multisig, bytes payload);

/// @title MockTimelock - Mock of Timelock contract for community multisig management
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelockCM {
    event CallScheduled(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay);

    /// @dev Executes the payload at the specified address.
    /// @param to Address to call.
    /// @param payload Bytes of payload.
    function execute(address to, bytes memory payload) external {
        (bool success, ) = to.call(payload);
        if (!success) {
            revert ExecFailed(to, payload);
        }
    }

    /// @dev Executes payloads for specified addresses.
    /// @param targets Target addresses.
    /// @param payloads Bytes of payloads.
    function executeBatch(address[] memory targets, bytes[] memory payloads) external {
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, ) = targets[i].call(payloads[i]);
            if (!success) {
                revert ExecFailed(targets[i], payloads[i]);
            }
        }
    }

    /// @dev Mock of a schedule function.
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external {
        emit CallScheduled(target, value, data, predecessor, salt, delay);
    }

    /// @dev Mock of a scheduleBatch function.
    function scheduleBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external {
        emit CallScheduled(targets[0], values[0], datas[0], predecessor, salt, delay);
    }
}