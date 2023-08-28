// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

error ExecFailed(address multisig, bytes payload);

/// @title MockTimelock - Mock of Timelock contract for community multisig management
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelockCM {
    // Multisig address
    address public multisig;

    function setMultisig(address _multisig) external {
        multisig = _multisig;
    }

    /// @dev Executes the payload at the Fx Root address.
    /// @param payload Bytes of payload.
    function execute(bytes memory payload) external {
        (bool success, ) = multisig.call(payload);
        if (!success) {
            revert ExecFailed(multisig, payload);
        }
    }
}