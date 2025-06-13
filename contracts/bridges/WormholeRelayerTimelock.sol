// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IWormhole {
    /// @dev Returns the price to request a relay to chain `targetChain`, using the default delivery provider
    ///
    /// @param targetChain in Wormhole Chain ID format
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress` (in targetChain currency units)
    /// @param gasLimit gas limit with which to call `targetAddress`.
    /// @return nativePriceQuote Price, in units of current chain currency, that the delivery provider charges to perform the relay
    /// @return targetChainRefundPerGasUnused amount of target chain currency that will be refunded per unit of gas unused,
    ///         if a refundAddress is specified.
    ///         Note: This value can be overridden by the delivery provider on the target chain. The returned value here should be considered to be a
    ///         promise by the delivery provider of the amount of refund per gas unused that will be returned to the refundAddress at the target chain.
    ///         If a delivery provider decides to override, this will be visible as part of the emitted Delivery event on the target chain.
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
    ///        `targetChainRefundPerGasUnused` rate quoted by the delivery provider
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
    event LeftoversRefunded(address indexed sender, uint256 leftovers);

    // Timelock address
    address public immutable timelock;
    // L1 Wormhole Relayer address that sends the message across the bridge
    address public immutable wormholeRelayer;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev WormholeRelayer constructor.
    /// @param _wormholeRelayer Wormhole relayer address.
    constructor(address _timelock, address _wormholeRelayer) {
        // Check for zero addresses
        if (_timelock == address(0) || _wormholeRelayer == address(0)) {
            revert ZeroAddress();
        }

        timelock = _timelock;
        wormholeRelayer = _wormholeRelayer;
    }

    /// @dev Relays a payload via Wormhole relayer to the address `targetAddress` on chain `targetChain`
    ///      with gas limit `gasLimit` and `msg.value` equal to `receiverValue`.
    /// @notice This function takes arbitrary `msg.value` and adjusts the cost for relayer exact amount.
    /// @param targetChain in Wormhole Chain ID format.
    /// @param targetAddress address to call on targetChain (that implements IWormholeReceiver).
    /// @param payload arbitrary bytes to pass in as parameter in call to `targetAddress`.
    /// @param receiverValue msg.value that delivery provider should pass in for call to `targetAddress`
    ///        in `targetChain` currency units.
    /// @param gasLimit gas limit with which to call `targetAddress`. Any units of gas unused will be refunded according to the
    ///        `targetChainRefundPerGasUnused` rate quoted by the delivery provider.
    /// @param refundChain The chain to deliver any refund to, in Wormhole Chain ID format.
    /// @param refundChainAddress The address on `refundChain` to deliver any refund to.
    /// @return sequence Sequence number of published VAA containing delivery instructions.
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundChainAddress,
        address refundValueAddress
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
        if (targetAddress == address(0) || refundChainAddress == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (targetChain == 0 || payload.length == 0 || gasLimit == 0 || refundChain == 0) {
            revert ZeroValue();
        }

        // Get the message cost in order to adjust leftovers
        (uint256 cost, ) = IWormhole(wormholeRelayer).quoteEVMDeliveryPrice(targetChain, receiverValue, gasLimit);

        // Check fot msg.value to cover the cost
        if (cost > msg.value) {
            revert LowerThan(msg.value, cost);
        }

        // Return value leftovers
        uint256 leftovers = msg.value - cost;

        // Send leftover amount back to the sender, if any
        if (leftovers > 0) {
            // If refundValueAddress is zero, fallback to tx.origin
            if (refundValueAddress == address(0)) {
                refundValueAddress = tx.origin;
            }

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = refundValueAddress.call{value: leftovers}("");
            if (!success) {
                revert TransferFailed(refundValueAddress, leftovers);
            }

            emit LeftoversRefunded(refundValueAddress, leftovers);
        }

        // Send payload via the Wormhole relayer with exact required cost
        sequence = IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(targetChain, targetAddress, payload,
            receiverValue, gasLimit, refundChain, refundChainAddress);

        _locked = 1;
    }
}