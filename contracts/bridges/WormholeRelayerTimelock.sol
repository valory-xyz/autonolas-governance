// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev ERC20 token interface.
interface IERC20 {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWormhole {
    /// @dev Returns the price to request a relay to chain `targetChain`, using the default delivery provider
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`.
    /// @return nativePriceQuote Price, in units of current chain currency, that the delivery provider charges to perform the relay
    /// @return targetChainRefundPerGasUnused amount of target chain currency that will be refunded per unit of gas unused,
    ///        if a refundAddress is specified.
    ///        Note: This value can be overridden by the delivery provider on the target chain. The returned value here should be considered to be a
    ///        promise by the delivery provider of the amount of refund per gas unused that will be returned to the refundAddress at the target chain.
    ///        If a delivery provider decides to override, this will be visible as part of the emitted Delivery event on the target chain.
    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external view returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    /// @dev Publishes an instruction for the default delivery provider
    /// to relay a payload to the address `targetAddress` on chain `targetChain`
    /// with gas limit `gasLimit` and `msg.value` equal to `receiverValue`
    ///
    /// Any refunds (from leftover gas) will be sent to `refundAddress` on chain `refundChain`
    /// `targetAddress` must implement the IWormholeReceiver interface
    ///
    /// This function must be called with `msg.value` equal to `quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit)`
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver)
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    ///       `targetChainRefundPerGasUnused` rate quoted by the delivery provider
    /// @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format
    /// @param refundAddress The address on `refundChain` to deliver any refund to
    /// @return sequence sequence number of published VAA containing delivery instructions
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) external payable returns (uint64 sequence);


    /// @dev Transfers tokens through portal.
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param targetChain in Wormhole Chain ID format.
    /// @param recipient Recipient address to call on targetChain in bytes32 format.
    /// @param arbiterFee Optional amount of tokens as relayer fee, claimed by relayers who submit VAA on target chain.
    /// @param nonce Nonce value.
    /// @return sequence Sequence number of published VAA containing delivery instructions.
    function transferTokens(address token, uint256 amount, uint16 targetChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce) external payable returns (uint64 sequence);

    /// @dev Gets Wormhole Core message fee.
    function messageFee() external view returns (uint256);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Unauthorized account.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @dev Failure of a native token transfer.
/// @param to Address `to`.
/// @param amount Token amount.
error TransferFailed(address to, uint256 amount);

// @dev Reentrancy guard.
error ReentrancyGuard();

/// @title WormholeRelayerTimelock - Smart contract for the contract interaction with wormhole relayer by timelock with any msg.value
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract WormholeRelayerTimelock {
    event MessageSent(uint256 indexed sequence, address indexed targetAddress, uint256 targetChain, uint256 receiverValue, bytes payload);
    event TokensSent(uint256 indexed sequence, bytes32 indexed recipient, uint256 targetChain, uint256 amount, uint256 nonce);
    event LeftoversRefunded(address indexed sender, uint256 leftovers);

    // Message transfer minimum gas limit for L2
    uint256 public constant MIN_GAS_LIMIT = 2_000_000;

    // Timelock address
    address public immutable timelock;
    // L1 Wormhole Core address
    address public immutable wormholeCore;
    // L1 Wormhole Relayer address that sends the message across the bridge
    address public immutable wormholeRelayer;
    // L1 Wormhole Token Bridge aka Wrapped Token Transfers (WTT) address that sends tokens across the bridge
    address public immutable wormholeTokenBridge;
    // Chain to deliver any refund to, in Wormhole Chain ID format
    uint16 public immutable refundChainId;

    // Nonce value: it is safe to assume it is not going to overflow for next 100+ years, even if called every second
    uint32 public nonce;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev WormholeRelayerTimelock constructor.
    /// @param _timelock Timelock address.
    /// @param _wormholeCore Wormhole core address.
    /// @param _wormholeRelayer Wormhole relayer address.
    /// @param _wormholeTokenBridge Wormhole token bridge address.
    /// @param _refundChainId Refund chain Id in Wormhole format: must be set to corresponding block.chainid.
    constructor(address _timelock, address _wormholeCore, address _wormholeRelayer, address _wormholeTokenBridge, uint16 _refundChainId) {
        // Check for zero addresses
        if (_timelock == address(0) || _wormholeCore == address(0) || _wormholeRelayer == address(0) || _wormholeTokenBridge == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero value
        if (_refundChainId == 0) {
            revert ZeroValue();
        }

        timelock = _timelock;
        wormholeCore = _wormholeCore;
        wormholeRelayer = _wormholeRelayer;
        wormholeTokenBridge = _wormholeTokenBridge;
        refundChainId = _refundChainId;
    }

    function _manageFee(uint256 cost, address refundAddress) internal {
        // Check fot msg.value to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Return value leftovers
        uint256 leftovers = msg.value - cost;

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = refundAddress.call{value: leftovers}("");
            if (!success) {
                revert TransferFailed(refundAddress, leftovers);
            }

            emit LeftoversRefunded(refundAddress, leftovers);
        }
    }

    /// @dev Relays a payload via Wormhole relayer to the address `targetAddress` on chain `targetChain`
    ///     with gas limit `gasLimit` and `msg.value` equal to `receiverValue`.
    /// @notice This function takes arbitrary `msg.value` and adjusts the cost for relayer exact amount.
    /// @notice `refundAddress` is the same for message fee refund, and excessive cost refund.
    /// @param targetChain in Wormhole Chain ID format.
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver).
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`.
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress`
    ///       in `targetChain` currency units.
    /// @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according
    ///       to the `targetChainRefundPerGasUnused` rate quoted by the delivery provider.
    /// @param refundAddress The address on `refundChainId` to deliver any refund to.
    /// @return sequence Sequence number of published VAA containing delivery instructions.
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        address refundAddress
    ) external payable returns (uint64 sequence) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for timelock access
        if (msg.sender != timelock) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Check for zero addresses
        if (targetAddress == address(0) || refundAddress == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (targetChain == 0 || payload.length == 0) {
            revert ZeroValue();
        }

        // Check for message gas limit
        if (gasLimit < MIN_GAS_LIMIT) {
            gasLimit = MIN_GAS_LIMIT;
        }

        // Get the message cost in order to adjust leftovers
        (uint256 cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);

        // Manage fee
        _manageFee(cost, refundAddress);

        // Send payload via the Wormhole relayer with exact required cost
        sequence = IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(targetChain, targetAddress, payload,
            receiverValue, gasLimit, refundChainId, refundAddress);

        emit MessageSent(sequence, targetAddress, targetChain, receiverValue, payload);

        _locked = 1;
    }

    /// @dev Transfers tokens.
    /// @notice Token amount must be transferred to `address(this)` prior to this function call.
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param targetChain in Wormhole Chain ID format.
    /// @param recipient Recipient address to call on targetChain in bytes32 format.
    /// @param refundAddress The address on `refundChainId` to deliver any refund to.
    /// @return sequence Sequence number of published VAA containing delivery instructions.
    function transferTokens(address token, uint256 amount, uint16 targetChain, bytes32 recipient, address refundAddress) external payable returns (uint64 sequence) {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for timelock access
        if (msg.sender != timelock) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Check for zero addresses
        if (token == address(0) || refundAddress == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (targetChain == 0 || recipient == 0 || amount == 0) {
            revert ZeroValue();
        }

        // Get the message cost in order to adjust leftovers
        uint256 cost = IWormhole(wormholeCore).messageFee();

        // Approve token for token bridge
        IERC20(token).approve(wormholeTokenBridge, amount);

        // Manage fee
        _manageFee(cost, refundAddress);

        uint32 localNonce = nonce;

        // Transfer tokens
        // Note that arbiter fee is set to zero as it is optional
        sequence = IWormhole(wormholeTokenBridge).transferTokens{value: cost}(token, amount, targetChain, recipient, 0, localNonce);

        // Update nonce
        nonce = localNonce + 1;

        emit TokensSent(sequence, recipient, targetChain, amount, localNonce);

        _locked = 1;
    }
}