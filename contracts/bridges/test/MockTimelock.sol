// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error ExecFailed(address fxRoot, bytes payload);

/// @title MockTimelock - Mock of Timelock contract on the L1 side
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelock {
    // Fx Root address on L1
    address public immutable fxRoot;

    constructor(address _fxRoot) {
        fxRoot = _fxRoot;
    }

    /// @dev Executes the payload at the Fx Root address.
    /// @param payload Bytes of payload.
    function execute(bytes memory payload) external payable {
        (bool success, ) = fxRoot.call{value: msg.value}(payload);
        if (!success) {
            revert ExecFailed(fxRoot, payload);
        }
    }
}