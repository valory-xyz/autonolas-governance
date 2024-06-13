// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

error ExecFailed(address relayer, bytes payload);

/// @title MockTimelock - Mock of Timelock contract on the L1 side
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelock {
    // Fx Root address on L1
    address public immutable relayer;

    constructor(address _relayer) {
        relayer = _relayer;
    }

    /// @dev Executes the payload at the Fx Root address.
    /// @param payload Bytes of payload.
    function execute(bytes memory payload) external payable {
        (bool success, ) = relayer.call{value: msg.value}(payload);
        if (!success) {
            revert ExecFailed(relayer, payload);
        }
    }
}