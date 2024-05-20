// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev The combination of target and selector is not authorized.
/// @param target Target address.
/// @param selector Function selector.
/// @param chainId Chain Id.
error NotAuthorized(address target, bytes4 selector, uint256 chainId);

/// @title VerifyData - Smart contract for verifying the Guard CM data
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract VerifyData {
    // Mapping of (target address | bytes4 selector | uint64 chain Id) => enabled / disabled
    mapping(uint256 => bool) public mapAllowedTargetSelectorChainIds;

    /// @dev Verifies authorized combinations of target and selector.
    /// @notice The bottom-most internal function is still not "view" since some reverts are not explicitly handled
    /// @param target Target address.
    /// @param data Payload bytes.
    /// @param chainId Chain Id.
    function _verifyData(address target, bytes memory data, uint256 chainId) internal {
        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetSelectorChainId = uint256(uint160(target));
        // selector occupies next 32 bits
        bytes4 targetSelector = bytes4(data);
        targetSelectorChainId |= uint256(uint32(targetSelector)) << 160;
        // chainId occupies next 64 bits
        targetSelectorChainId |= chainId << 192;

        // Check the authorized combination of target and selector
        if (!mapAllowedTargetSelectorChainIds[targetSelectorChainId]) {
            revert NotAuthorized(target, targetSelector, chainId);
        }
    }
}