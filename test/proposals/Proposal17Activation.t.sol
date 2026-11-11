// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal17Activation} from "../../scripts/proposals/proposal_17/Proposal17Activation.s.sol";

contract Proposal17Emit is Test {
    Proposal17Activation internal p;

    function setUp() public {
        p = new Proposal17Activation();
    }

    function test_emit() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            p.buildProposal();
        assertEq(targets.length, 28, "expected 28 entries");
        uint256 totalValue;
        for (uint256 i; i < targets.length; ++i) {
            console2.log("---- entry", i);
            console2.log("target", targets[i]);
            console2.log("value ", values[i]);
            console2.logBytes(calldatas[i]);
            totalValue += values[i];
        }
        console2.log("total ETH value (wei):", totalValue);
        bytes32 descHash = keccak256(bytes(description));
        console2.log("descriptionHash:");
        console2.logBytes32(descHash);
        bytes32 pid = keccak256(abi.encode(targets, values, calldatas, descHash));
        console2.log("proposalId (hex):");
        console2.logBytes32(pid);
        console2.log("proposalId (uint):", uint256(pid));
    }
}
