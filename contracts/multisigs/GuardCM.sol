// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as an owner.
error ManagerOnly(address sender, address manager);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Numberf of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev No delegatecall is allowed.
error NoDelegateCall();

/// @dev No self multisig call is allowed.
error NoSelfCall();

/// @dev The combination of target and selector is not authorized.
/// @param target Target address.
/// @param selector Function selector.
error NotAuthorized(address target, bytes4 selector);

/// @title GuardCM - Smart contract for Gnosis Safe community multisig guard
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract GuardCM {
    event GovernorUpdated(address indexed governor);
    event SetTargetSelectors(address[] indexed targets, bytes4[] indexed selectors, bool[] statuses);

    // Owner address
    address public immutable owner;
    // Multisig address
    address public immutable multisig;
    // Governor address
    address public governor;

    // Guard pause possibility
    uint8 public paused = 1;
    
    // Mapping of address + bytes4 selector => enabled / disabled
    mapping(uint256 => bool) public mapAllowedTargetSelectors;

    // Schedule selector
    bytes4 public constant SCHEDULE = bytes4(keccak256(bytes("schedule(address,uint256,bytes,bytes32,bytes32,uint256)")));

    constructor(address _timelock, address _multisig, address _governor) {
        owner = _timelock;
        multisig = _multisig;
        governor = _governor;
    }

    /// @dev Changes the governor.
    /// @param newGovernor Address of a new governor.
    function changeGovernor(address newGovernor) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newGovernor == address(0)) {
            revert ZeroAddress();
        }

        governor = newGovernor;
        emit GovernorUpdated(newGovernor);
    }

    /// @dev Verifies authorized target and selector in the schedule function call.
    /// @param data Data in bytes.
    function _verifySchedule(bytes memory data) internal {
        //address,uint256,bytes,bytes32,bytes32,uint256
        bytes memory payload = new bytes(data.length - 4);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Decode the data in the schedule function
        (address target, uint256 value, bytes memory callData, , , ) =
            abi.decode(payload, (address, uint256, bytes, bytes32, bytes32, uint256));

        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetSelector = uint256(uint160(target));
        // selector occupies next 32 bits
        targetSelector |= uint256(uint32(bytes4(callData))) << 160;

        // Check the authorized combination of target and selector
        if (!mapAllowedTargetSelectors[targetSelector]) {
            revert NotAuthorized(target, bytes4(callData));
        }
    }

    /// @dev Checks the transaction for authorized arguments.
    /// @notice Scheduling in timelock in checked against authorized targets and signatures.
    /// @notice No self-multisig function calls are allowed.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param safeTxGas Gas that should be used for the Safe transaction.
    /// @param baseGas Gas costs that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
    /// @param gasPrice Gas price that should be used for the payment calculation.
    /// @param gasToken Token address (or 0 if ETH) that is used for the payment.
    /// @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v}).
    /// @param msgSender msg.sender of a Safe transaction.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external {
        // Just return if paused
        if (paused == 1) {
            // Call to the timelock
            if (to == owner) {
                // No delegatecall is allowed
                if (operation == Enum.Operation.DelegateCall) {
                    revert NoDelegateCall();
                }

                // Data length is too short: less than a size of a selector
                if (data.length < 4) {
                    revert IncorrectDataLength(data.length, 4);
                }

                // Get the function signature
                bytes4 functionSig = bytes4(data);
                // Check the schedule function authorized parameters
                // All other functions are not checked
                if (functionSig == SCHEDULE) {
                    _verifySchedule(data);
                }
            } else if (to == multisig) {
                // No self multisig call is allowed
                revert NoSelfCall();
            }
        }
    }

    /// @dev Authorizes combinations of targets and selectors.
    /// @param targets Array of target addresses.
    /// @param selectors Array of selectors for targets.
    /// @param statuses Authorize if true, and restrict otherwise.
    function setTargetSelectors(address[] memory targets, bytes4[] memory selectors, bool[] memory statuses) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        // Check array length
        if (targets.length != selectors.length || targets.length != statuses.length) {
            revert WrongArrayLength(targets.length, selectors.length);
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            // Push a pair of key defining variables into one key
            // target occupies first 160 bits
            uint256 targetSelector = uint256(uint160(targets[i]));
            // selector occupies next 32 bits
            targetSelector |= uint256(uint32(selectors[i])) << 160;

            // Set the status of the target and selector combination
            mapAllowedTargetSelectors[targetSelector] = statuses[i];
        }

        emit SetTargetSelectors(targets, selectors, statuses);
    }
    
    function pause(uint256 proposalId) external {
        // Check for the multisig access
        if (msg.sender != multisig) {
            revert ManagerOnly(msg.sender, multisig);
        }
        
        paused = 2;
    }

    function unpause() external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
    }

    /// @dev Guards the multisig call after its execution.
    function checkAfterExecution(bytes32, bool) external {}
}