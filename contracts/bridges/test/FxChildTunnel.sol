// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FxBaseChildTunnel} from "fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";

/// @title FxChildTunnel - Smart contract for the child tunnel bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract FxChildTunnel is FxBaseChildTunnel {
    event MessageReceived(uint256 indexed stateId, address indexed sender, bytes message);

    constructor(address _fxChild) FxBaseChildTunnel(_fxChild) {}

    /// @dev Process message received from Root Tunnel.
    /// @notice This is called by onStateReceive function. Since it is called via a system call,
    ///         any event will not be emitted during its execution.
    /// @param stateId unique state id
    /// @param sender root message sender
    /// @param message bytes message that was sent from Root Tunnel
    function _processMessageFromRoot(uint256 stateId, address sender, bytes memory message) internal override {
        emit MessageReceived(stateId, sender, message);
    }
}