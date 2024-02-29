// Sources flattened with hardhat v2.20.1 https://hardhat.org

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Interface to the CrossDomainMessenger (CDM) Contract Proxy.
interface ICrossDomainMessenger {
    function xDomainMessageSender() external returns (address);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Only self contract is allowed to call the function.
/// @param sender Sender address.
/// @param instance Required contract instance address.
error SelfCallOnly(address sender, address instance);

/// @dev Only `CDMContractProxyHome` is allowed to call the function.
/// @param sender Sender address.
/// @param CDMContractProxyHome Required CDM Contract Proxy (Home) address.
error CDMContractProxyHomeOnly(address sender, address CDMContractProxyHome);

/// @dev Only on behalf of `foreignGovernor` the function is allowed to process the data.
/// @param sender Sender address.
/// @param foreignGovernor Required Foreign Governor address.
error ForeignGovernorOnly(address sender, address foreignGovernor);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Provided value is bigger than the actual balance.
/// @param value Provided value.
/// @param balance Actual balance.
error InsufficientBalance(uint256 value, uint256 balance);

/// @dev Target execution failed.
/// @param target Target address.
/// @param value Provided value.
/// @param payload Provided payload.
error TargetExecFailed(address target, uint256 value, bytes payload);

/// @title OptimismMessenger - Smart contract for the governor home (Optimism) bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract OptimismMessenger {
    event FundsReceived(address indexed sender, uint256 value);
    event ForeignGovernorUpdated(address indexed foreignMessageSender);
    event MessageReceived(address indexed foreignMessageSender, bytes data);

    // Default payload data length includes the number of bytes of at least one address (20 bytes or 160 bits),
    // value (12 bytes or 96 bits) and the payload size (4 bytes or 32 bits)
    uint256 public constant DEFAULT_DATA_LENGTH = 36;
    // CDM Contract Proxy (Home) address on L2 that receives the message across the bridge from the foreign L1 network
    address public immutable CDMContractProxyHome;
    // Foreign governor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public foreignGovernor;

    /// @dev OptimismMessenger constructor.
    /// @param _CDMContractProxyHome CDM Contract Proxy (Home) address (Optimism).
    /// @param _foreignGovernor Foreign Governor address (ETH).
    constructor(address _CDMContractProxyHome, address _foreignGovernor) {
        // Check fo zero addresses
        if (_CDMContractProxyHome == address(0) || _foreignGovernor == address(0)) {
            revert ZeroAddress();
        }

        CDMContractProxyHome = _CDMContractProxyHome;
        foreignGovernor = _foreignGovernor;
    }

    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    /// @dev Changes the Foreign Governor address (original Timelock).
    /// @notice The only way to change the Foreign Governor address is by the Timelock on L1 to request that change.
    ///         This triggers a self-contract transaction of OptimismMessenger that changes the Foreign Governor address.
    /// @param newForeignGovernor New Foreign Governor address.
    function changeForeignGovernor(address newForeignGovernor) external {
        // Check if the change is authorized by the previous governor itself
        // This is possible only if all the checks in the message process function pass and the contract calls itself
        if (msg.sender != address(this)) {
            revert SelfCallOnly(msg.sender, address(this));
        }

        // Check for the zero address
        if (newForeignGovernor == address(0)) {
            revert ZeroAddress();
        }

        foreignGovernor = newForeignGovernor;
        emit ForeignGovernorUpdated(newForeignGovernor);
    }

    /// @dev Processes a message received from the CDM Contract Proxy (Home) contract.
    /// @notice The sender must be the Foreign Governor address (Timelock).
    /// @param data Bytes message sent from the CDM Contract Proxy (Home) contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
    function processMessageFromForeign(bytes memory data) external payable {
        // Check for the CDM Contract Proxy (Home) address
        if (msg.sender != CDMContractProxyHome) {
            revert CDMContractProxyHomeOnly(msg.sender, CDMContractProxyHome);
        }

        // Check for the Foreign Governor address
        address governor = foreignGovernor;
        address bridgeGovernor = ICrossDomainMessenger(CDMContractProxyHome).xDomainMessageSender();
        if (bridgeGovernor != governor) {
            revert ForeignGovernorOnly(bridgeGovernor, governor);
        }

        // Check for the correct data length
        uint256 dataLength = data.length;
        if (dataLength < DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
        }

        // Unpack and process the data
        for (uint256 i = 0; i < dataLength;) {
            address target;
            uint96 value;
            uint32 payloadLength;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // First 20 bytes is the address (160 bits)
                i := add(i, 20)
                target := mload(add(data, i))
                // Offset the data by 12 bytes of value (96 bits)
                i := add(i, 12)
                value := mload(add(data, i))
                // Offset the data by 4 bytes of payload length (32 bits)
                i := add(i, 4)
                payloadLength := mload(add(data, i))
            }

            // Check for the zero address
            if (target == address(0)) {
                revert ZeroAddress();
            }

            // Check for the value compared to the contract's balance
            if (value > address(this).balance) {
                revert InsufficientBalance(value, address(this).balance);
            }

            // Get the payload
            bytes memory payload = new bytes(payloadLength);
            for (uint256 j = 0; j < payloadLength; ++j) {
                payload[j] = data[i + j];
            }
            // Offset the data by the payload number of bytes
            i += payloadLength;

            // Call the target with the provided payload
            (bool success, ) = target.call{value: value}(payload);
            if (!success) {
                revert TargetExecFailed(target, value, payload);
            }
        }

        // Emit received message
        emit MessageReceived(governor, data);
    }
}
