// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./OLAS.sol";
import "./veOLAS.sol";

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

contract DeploymentFactory {
    event OwnerUpdated(address indexed owner);

    // OLAS deployed address
    address public olasAddress;
    // veOLAS deployed address
    address public veOLASAddress;
    // Owner address
    address public owner;

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    constructor() {
        owner = msg.sender;
    }

    /// @dev Deploys `OLAS` contract via the `create2` method.
    /// @param salt Specified salt.
    function deployOLAS(bytes32 salt) external {
        // Check for the ownership
        if (owner != msg.sender) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Deploy OLAS contract
        olasAddress = Create2.deploy(0, salt, abi.encodePacked(type(OLAS).creationCode));

        // Change minter and owner of the OLAS contract to the msg.sender
        OLAS(olasAddress).changeMinter(msg.sender);
        OLAS(olasAddress).changeOwner(msg.sender);
    }

    /// @dev Computes `OLAS` contract address.
    /// @param salt Specified salt.
    /// @return Computed token address.
    function computeOLASAddress(bytes32 salt) external view returns (address){
        return Create2.computeAddress(salt, keccak256(abi.encodePacked(type(OLAS).creationCode)));
    }

    /// @dev Deploys `veOLAS` contract via the `create2` method.
    /// @param salt Specified salt.
    function deployVeOLAS(bytes32 salt, address token) external {
        // Check for the ownership
        if (owner != msg.sender) {
            revert OwnerOnly(msg.sender, owner);
        }

        veOLASAddress = Create2.deploy(0, salt, abi.encodePacked(type(veOLAS).creationCode, abi.encode(token, "Voting Escrow OLAS", "veOLAS")));
    }

    /// @dev Computes `veOLAS` contract address.
    /// @param salt Specified salt.
    /// @return Computed token address.
    function computeVeOLASAddress(bytes32 salt, address token) external view returns (address){
        return Create2.computeAddress(salt, keccak256(abi.encodePacked(type(veOLAS).creationCode, abi.encode(token, "Voting Escrow OLAS", "veOLAS"))));
    }
}