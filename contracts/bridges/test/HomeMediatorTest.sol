// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title HomeMediatorTest - Smart contract for the governor home (gnosis chain) bridge implementation transfer data test
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract HomeMediatorTest {
    event MessageReceived(address indexed sender, bytes data);

    /// @dev Process message received from the AMB Mediator contract.
    /// @param data Bytes message sent from the AMB Mediator contract.
    function processMessageFromForeign(bytes memory data) external {
        // Emit received message
        emit MessageReceived(msg.sender, data);
    }
}