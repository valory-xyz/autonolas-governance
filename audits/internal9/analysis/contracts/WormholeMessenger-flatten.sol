// Sources flattened with hardhat v2.20.1 https://hardhat.org

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Only self contract is allowed to call the function.
/// @param sender Sender address.
/// @param instance Required contract instance address.
error SelfCallOnly(address sender, address instance);

/// @dev Only `wormholeRelayer` is allowed to call the function.
/// @param sender Sender address.
/// @param wormholeRelayer Required L2 Wormhole Relayer address.
error wormholeRelayerOnly(address sender, address wormholeRelayer);

/// @dev Wrong source chain Id.
/// @param received Chain Id received.
/// @param required Required chain Id.
error WrongSourceChainId(uint256 received, uint256 required);

/// @dev Only on behalf of `sourceGovernor` the function is allowed to process the data.
/// @param sender Sender address.
/// @param sourceGovernor Required source governor address.
error SourceGovernorOnly(address sender, address sourceGovernor);

/// @dev The message with a specified hash has already been delivered.
/// @param deliveryHash Delivery hash.
error AlreadyDelivered(bytes32 deliveryHash);

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

/// @title WormholeMessenger - Smart contract for the governor bridge communication via wormhole
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeMessenger {
    event FundsReceived(address indexed sender, uint256 value);
    event SourceGovernorUpdated(address indexed sourceMessageSender);
    event MessageReceived(address indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint256 sourceChain);

    // Default payload data length includes the number of bytes of at least one address (20 bytes or 160 bits),
    // value (12 bytes or 96 bits) and the payload size (4 bytes or 32 bits)
    uint256 public constant DEFAULT_DATA_LENGTH = 36;
    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source governor chain Id
    uint16 public immutable sourceGovernorChainId;
    // Source governor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public sourceGovernor;
    // Mapping of delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeMessenger constructor.
    /// @param _wormholeRelayer L2 Wormhole Relayer address.
    /// @param _sourceGovernor Source governor address (ETH).
    /// @param _sourceGovernorChainId Source governor wormhole format chain Id.
    constructor(address _wormholeRelayer, address _sourceGovernor, uint16 _sourceGovernorChainId) {
        // Check for zero addresses
        if (_wormholeRelayer == address(0) || _sourceGovernor == address(0)) {
            revert ZeroAddress();
        }

        // Check source governor chain Id
        if (_sourceGovernorChainId == 0) {
            revert ZeroValue();
        }

        wormholeRelayer = _wormholeRelayer;
        sourceGovernor = _sourceGovernor;
        sourceGovernorChainId = _sourceGovernorChainId;
    }

    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    /// @dev Changes the source governor address (original Timelock).
    /// @notice The only way to change the source governor address is by the Timelock on L1 to request that change.
    ///         This triggers a self-contract transaction of WormholeMessenger that changes the source governor address.
    /// @param newSourceGovernor New source governor address.
    function changeSourceGovernor(address newSourceGovernor) external {
        // Check if the change is authorized by the previous governor itself
        // This is possible only if all the checks in the message process function pass and the contract calls itself
        if (msg.sender != address(this)) {
            revert SelfCallOnly(msg.sender, address(this));
        }

        // Check for the zero address
        if (newSourceGovernor == address(0)) {
            revert ZeroAddress();
        }

        sourceGovernor = newSourceGovernor;
        emit SourceGovernorUpdated(newSourceGovernor);
    }

    /// @dev Processes a message received from L2 Wormhole Relayer contract.
    /// @notice The sender must be the source governor address (Timelock).
    /// @param data Bytes message sent from L2 Wormhole Relayer contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
    /// @param sourceAddress The (wormhole format) address on the sending chain which requested this delivery.
    /// @param sourceChain The wormhole chain Id where this delivery was requested.
    /// @param deliveryHash The VAA hash of the deliveryVAA.
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        // Check L2 Wormhole Relayer address
        if (msg.sender != wormholeRelayer) {
            revert wormholeRelayerOnly(msg.sender, wormholeRelayer);
        }

        // Check the source chain Id
        if (sourceChain != sourceGovernorChainId) {
            revert WrongSourceChainId(sourceChain, sourceGovernorChainId);
        }

        // Check for the source governor address
        address governor = sourceGovernor;
        address bridgeGovernor = address(uint160(uint256(sourceAddress)));
        if (bridgeGovernor != governor) {
            revert SourceGovernorOnly(bridgeGovernor, governor);
        }

        // Check the delivery hash uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        }
        mapDeliveryHashes[deliveryHash] = true;

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
        emit MessageReceived(governor, data, deliveryHash, sourceChain);
    }
}
