// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
    ///
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

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @title WormholeRelayer - Smart contract for the contract interaction with wormhole relayer with any msg.value
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract WormholeRelayer {
    event LeftoversRefunded(address indexed sender, uint256 leftovers);

    // L1 Wormhole Relayer address that sends the message across the bridge
    address public immutable wormholeRelayer;

    /// @dev WormholeRelayer constructor.
    /// @param _wormholeRelayer Wormhole relayer address.
    constructor(address _wormholeRelayer) {
        wormholeRelayer = _wormholeRelayer;
    }

    /// @dev Relays a payload via Wormhole relayer to the address `targetAddress` on chain `targetChain`
    ///      with gas limit `gasLimit` and `msg.value` equal to `receiverValue`.
    /// @notice This function takes arbitrary `msg.value` and adjusts the cost for relayer exact amount.
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
    ) external payable returns (uint64) {
        // Check for zero addresses
        if (targetAddress == address(0) || refundAddress == address(0)) {
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
            // If the call fails, ignore to avoid the attack that would prevent this function from executing
            // solhint-disable-next-line avoid-low-level-calls
            tx.origin.call{value: leftovers}("");

            emit LeftoversRefunded(tx.origin, leftovers);
        }

        // Send payload via the Wormhole relayer with exact required cost
        return IWormhole(wormholeRelayer).sendPayloadToEvm{value: cost}(targetChain, targetAddress, payload,
            receiverValue, gasLimit, refundChain, refundAddress);
    }
}