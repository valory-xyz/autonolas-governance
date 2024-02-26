// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Provided zero address.
error ZeroAddress();

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
/// @param sourceGovernor Required Source Governor address.
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

/// @title WormholeMessenger - Smart contract for the governor Wormhole bridge implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeMessenger {
    event FundsReceived(address indexed sender, uint256 value);
    event SourceGovernorUpdated(address indexed sourceMessageSender);
    event MessageReceived(address indexed sourceMessageSender, bytes data, bytes32 deliveryHash, uint16 sourceChain);

    // Default payload data length includes the number of bytes of at least one address (20 bytes or 160 bits),
    // value (12 bytes or 96 bits) and the payload size (4 bytes or 32 bits)
    uint256 public constant DEFAULT_DATA_LENGTH = 36;
    // Source governor chain Id
    uint16 public constant SOURCE_GOVERNOR_CHAIN_ID = 2;
    // L2 Wormhole Relayer address that receives the message across the bridge from the source L1 network
    address public immutable wormholeRelayer;
    // Source governor address on L1 that is authorized to propagate the transaction execution across the bridge
    address public sourceGovernor;
    // Mapping of delivery hashes
    mapping(bytes32 => bool) public mapDeliveryHashes;

    /// @dev WormholeMessenger constructor.
    /// @param _wormholeRelayer L2 Wormhole Relayer.
    /// @param _sourceGovernor Source Governor address (ETH).
    constructor(address _wormholeRelayer, address _sourceGovernor) {
        // Check fo zero addresses
        if (_wormholeRelayer == address(0) || _sourceGovernor == address(0)) {
            revert ZeroAddress();
        }

        wormholeRelayer = _wormholeRelayer;
        sourceGovernor = _sourceGovernor;
    }

    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    /// @dev Changes the Source Governor address (original Timelock).
    /// @notice The only way to change the Source Governor address is by the Timelock on L1 to request that change.
    ///         This triggers a self-contract transaction of WormholeMessenger that changes the Source Governor address.
    /// @param newSourceGovernor New Source Governor address.
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

    /// @dev Processes a message received from the L2 Wormhole Relayer contract.
    /// @notice The sender must be the Source Governor address (Timelock).
    /// @param data Bytes message sent from the L2 Wormhole Relayer contract. The data must be encoded as a set of
    ///        continuous transactions packed into a single buffer, where each transaction is composed as follows:
    ///        - target address of 20 bytes (160 bits);
    ///        - value of 12 bytes (96 bits), as a limit for all of Autonolas ecosystem contracts;
    ///        - payload length of 4 bytes (32 bits), as 2^32 - 1 characters is more than enough to fill a whole block;
    ///        - payload as bytes, with the length equal to the specified payload length.
    /**
     * @notice When a `send` is performed with this contract as the target, this function will be
     *     invoked by the WormholeRelayer contract
     *
     * NOTE: This function should be restricted such that only the Wormhole Relayer contract can call it.
     *
     * We also recommend that this function checks that `sourceChain` and `sourceAddress` are indeed who
     *       you expect to have requested the calling of `send` on the source chain
     *
     * The invocation of this function corresponding to the `send` request will have msg.value equal
     *   to the receiverValue specified in the send request.
     *
     * If the invocation of this function reverts or exceeds the gas limit
     *   specified by the send requester, this delivery will result in a `ReceiverFailure`.
     *
     * @param data - an arbitrary message which was included in the delivery by the
     *     requester. This message's signature will already have been verified (as long as msg.sender is the Wormhole Relayer contract)
     *
     * @param sourceAddress - the (wormhole format) address on the sending chain which requested
     *     this delivery.
     * @param sourceChain - the wormhole chain ID where this delivery was requested.
     * @param deliveryHash - the VAA hash of the deliveryVAA.
     *
     */
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        // Check for the L2 Wormhole Relayer address
        if (msg.sender != wormholeRelayer) {
            revert wormholeRelayerOnly(msg.sender, wormholeRelayer);
        }

        if (sourceChain != SOURCE_GOVERNOR_CHAIN_ID) {
            revert WrongSourceChainId(sourceChain, SOURCE_GOVERNOR_CHAIN_ID);
        }

        // Check for the Source Governor address
        address governor = sourceGovernor;
        address bridgeGovernor = address(uint160(uint256(sourceAddress)));

        if (bridgeGovernor != governor) {
            revert SourceGovernorOnly(bridgeGovernor, governor);
        }

        // Check the delivery hash for uniqueness
        if (mapDeliveryHashes[deliveryHash]) {
            revert AlreadyDelivered(deliveryHash);
        } else {
            mapDeliveryHashes[deliveryHash] = true;
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
        emit MessageReceived(governor, data, deliveryHash, sourceChain);
    }
}