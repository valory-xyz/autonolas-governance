// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Proposal18} from "../../scripts/proposals/proposal_18/Proposal18.s.sol";

/// @dev Asserts the committed artifacts AGREE WITH THE BUILDER, rather than merely being decodable:
///      every calldata.json entry (target, value, calldata) equals Proposal18.buildProposal(),
///      description.txt equals the builder's description byte-for-byte, and the proposalId /
///      descriptionHash recomputed from the committed artifacts equal the committed constants below.
///      This is the automated drift check the proposal checklist requires; it needs no RPC.
/// Run: cd <repo> && forge test --match-contract Proposal18Artifacts -vv
contract Proposal18Artifacts is Test {
    // Committed values — must match README.md / proposal_18.html / the submitted proposal.
    bytes32 constant EXPECTED_PROPOSAL_ID = 0xc672870b3758789a7f404c384c19e2863285db95ec14c3f81af3e431a97ae7ea;
    bytes32 constant EXPECTED_DESC_HASH   = 0x47d5bcb3a51d332ca4c08bc94f8d297746a50f71adb7459881dd055bd12b2a7e;

    string constant DIR = "scripts/proposals/proposal_18/";

    function test_artifacts_match_builder() public {
        Proposal18 p = new Proposal18();
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory desc) = p.buildProposal();

        // 1) description.txt == builder description (byte-for-byte), and its hash == committed.
        string memory fileDesc = vm.readFile(string.concat(DIR, "description.txt"));
        assertEq(keccak256(bytes(fileDesc)), keccak256(bytes(desc)), "description.txt != builder description");
        bytes32 descHash = keccak256(bytes(desc));
        assertEq(descHash, EXPECTED_DESC_HASH, "descriptionHash != committed");

        // 2) each calldata.json entry == builder entry.
        string memory json = vm.readFile(string.concat(DIR, "calldata.json"));
        assertEq(t.length, 3, "unexpected entry count");
        for (uint256 i; i < t.length; ++i) {
            string memory base = string.concat("$[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(json, string.concat(base, ".target")), t[i], "target mismatch");
            assertEq(vm.parseJsonBytes(json, string.concat(base, ".calldata")), c[i], "calldata mismatch");
            // value is stored as a JSON string ("0"); compare as string and assert the builder value too.
            assertEq(vm.parseJsonString(json, string.concat(base, ".value")), vm.toString(v[i]), "value mismatch");
        }

        // 3) proposalId recomputed from the (builder == committed) arrays equals the committed id.
        bytes32 pid = keccak256(abi.encode(t, v, c, descHash));
        assertEq(pid, EXPECTED_PROPOSAL_ID, "proposalId != committed");
    }
}
