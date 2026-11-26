// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Proposal20} from "../../scripts/proposals/proposal_20/Proposal20.s.sol";

/// @dev Asserts the committed artifacts AGREE WITH THE BUILDER, rather than merely being decodable:
///      every calldata.json entry (target, value, calldata) equals Proposal20.buildProposal(),
///      description.txt equals the builder's description byte-for-byte, and the proposalId /
///      descriptionHash recomputed from the committed artifacts equal the committed constants below.
///      This is the automated drift check the proposal checklist requires; it needs no RPC.
/// Run: cd <repo> && forge test --match-contract Proposal20Artifacts -vv
contract Proposal20Artifacts is Test {
    // Committed values — must match README.md / proposal_20.html / the submitted proposal.
    bytes32 constant EXPECTED_PROPOSAL_ID = 0x054aae970098f66ac399a88faf6f5181848ed56798c5bdb3a728160640a6ca59;
    bytes32 constant EXPECTED_DESC_HASH   = 0xc40673405bffa67856fedaeaa6728fa7526bdc161666d8a7f1d6a7426dc888f0;

    string constant DIR = "scripts/proposals/proposal_20/";

    function test_artifacts_match_builder() public {
        Proposal20 p = new Proposal20();
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory desc) = p.buildProposal();

        // 1) description.txt == builder description (byte-for-byte), and its hash == committed.
        string memory fileDesc = vm.readFile(string.concat(DIR, "description.txt"));
        assertEq(keccak256(bytes(fileDesc)), keccak256(bytes(desc)), "description.txt != builder description");
        bytes32 descHash = keccak256(bytes(desc));
        assertEq(descHash, EXPECTED_DESC_HASH, "descriptionHash != committed");

        // 2) each calldata.json entry == builder entry, AND the arrays are the same length (so an
        //    appended 4th action in calldata.json cannot slip past the 0..2 loop).
        string memory json = vm.readFile(string.concat(DIR, "calldata.json"));
        assertEq(t.length, 3, "unexpected builder entry count");
        // one "target" key per entry; asserts the JSON has no extra (e.g. appended 4th) action
        assertEq(_count(json, "\"target\""), t.length, "calldata.json entry count != builder");
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

    // Count non-overlapping occurrences of `needle` in `hay`.
    function _count(string memory hay, string memory needle) internal pure returns (uint256 n) {
        bytes memory h = bytes(hay);
        bytes memory nd = bytes(needle);
        if (nd.length == 0 || h.length < nd.length) return 0;
        for (uint256 i; i + nd.length <= h.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < nd.length; ++j) {
                if (h[i + j] != nd[j]) { match_ = false; break; }
            }
            if (match_) { ++n; i += nd.length - 1; }
        }
    }
}
