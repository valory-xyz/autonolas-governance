// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev prohibited action
error GuardDeny(address to, uint256 value, bytes data, address msgSender, uint256 i);

/// @title GuardCM - Smart contract for Gnosis Safe community multisig guard
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract GuardCM {
    event OwnerUpdated(address indexed owner);
    event MultisigUpdated(address indexed multisig);

    // Owner address
    address public owner;

    // Multisig address
    address public multisig;

    // Paused
    bool public paused = false;

    // Simple model: address => selector => bool
    struct Target {
        mapping(bytes4 => bool) allowedFunctions;
    }
    mapping(address => Target) private allowedTargets;

    bytes4 public constant SCHEDULE = bytes4(keccak256(bytes("schedule(address,uint256,bytes,bytes32,bytes32,uint256)")));

    constructor(address _timelock) {
        owner = _timelock;
        allowedTargets[owner].allowedFunctions[SCHEDULE] = true;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes the multisig address.
    /// @param newMultisig Address of a new multisig.
    function changeMultisig(address newMultisig) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newMultisig == address(0)) {
            revert ZeroAddress();
        }

        multisig = newMultisig;
        emit MultisigUpdated(newMultisig);
    }


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
        if(! paused) {
            if(to == owner) {
                // allow only schedule()
                // prohibited delegatecall
                if (operation == Enum.Operation.DelegateCall) {
                    revert GuardDeny(to, value, data, msgSender, 0);    
                }
                // prohibited sending ETH to timelock
                if (value > 0) {
                    revert GuardDeny(to, value, data, msgSender, 1);
                }
                // Function signature too short
                if (data.length < 4) {
                    revert GuardDeny(to, value, data, msgSender, 2);
                }
                // Not schedule()
                bytes4 functionSig = bytes4(data);
                if (! allowedTargets[to].allowedFunctions[functionSig]) {
                    revert GuardDeny(to, value, data, msgSender, 3);
                }
                // (x, addr, arr, myStruct) = abi.decode(data, (uint, address, uint[], MyStruct));
                bytes memory parsedMemory;
                assembly {
                    parsedMemory := add(data, /*BYTES_HEADER_SIZE*/32)
                }

            } else if (to == multisig) {
                // prohibited action
                revert GuardDeny(to, value, data, msgSender, 10);
            } else {
                // do nothing, TODO: remove lastest else
            }
        }
    }
}