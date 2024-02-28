// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BridgeMessenger} from "./BridgeMessenger.sol";

/// @dev Interface to the CrossDomainMessenger (CDM) Contract Proxy.
interface ICrossDomainMessenger {
    function xDomainMessageSender() external returns (address);
}

/// @title OptimismMessenger - Smart contract for the governor home (Optimism) bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract OptimismMessenger is BridgeMessenger {
    event MessageReceived(address indexed sourceMessageSender, bytes data);

    // CDM Contract Proxy (Home) address on L2 that receives the message across the bridge from the source L1 network
    address public immutable CDMContractProxyHome;

    /// @dev OptimismMessenger constructor.
    /// @param _CDMContractProxyHome CDM Contract Proxy (Home) address (Optimism).
    /// @param _sourceGovernor Source Governor address (ETH).
    constructor(address _CDMContractProxyHome, address _sourceGovernor) {
        // Check fo zero addresses
        if (_CDMContractProxyHome == address(0) || _sourceGovernor == address(0)) {
            revert ZeroAddress();
        }

        CDMContractProxyHome = _CDMContractProxyHome;
        sourceGovernor = _sourceGovernor;
    }

    /// @dev Processes a message received from the CDM Contract Proxy (Home) contract.
    /// @notice The sender must be the Source Governor address (Timelock).
    /// @param data Bytes message sent from the CDM Contract Proxy (Home) contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
    function processMessageFromSource(bytes memory data) external payable {
        // Check for the CDM Contract Proxy (Home) address
        if (msg.sender != CDMContractProxyHome) {
            revert TargetRelayerOnly(msg.sender, CDMContractProxyHome);
        }

        // Check for the Source Governor address
        address governor = sourceGovernor;
        address bridgeGovernor = ICrossDomainMessenger(CDMContractProxyHome).xDomainMessageSender();
        if (bridgeGovernor != governor) {
            revert SourceGovernorOnly(bridgeGovernor, governor);
        }

        // Process the data
        _processData(data);

        // Emit received message
        emit MessageReceived(governor, data);
    }
}