// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

error ExecFailed(address multisig, bytes payload);

/// @title MockTimelock - Mock of Timelock contract for community multisig management
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelockCM {
    event CallScheduled(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay);

    /// @dev Executes the payload at the Fx Root address.
    /// @param to Address to call.
    /// @param payload Bytes of payload.
    function execute(address to, bytes memory payload) external {
        (bool success, ) = to.call(payload);
        if (!success) {
            revert ExecFailed(to, payload);
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
}