// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 12 — un-nominate the remaining legacy staking contract nominees from VoteWeighting.
//
// Follow-up to the executed staking nominee cleanup (32 retired nominees removed; prepared as
// proposal 25 in the autonolas-registries repo alongside the de-whitelist proposal 24). This
// proposal removes the 20 LEGACY staking programs that were still live nominees at that time
// and have since been superseded by the new staking contract generation (Omenstrat, Polystrat,
// Basius, Optimus I-III), which stays nominated. All targets have zero current vote weight
// (weight has fully migrated to the new generation); removal is pure cleanup of the nominee set.
//
// NOT included (kept as live nominees): LST (Gnosis) — still carries active vote weight — and
// the 16 new-generation contracts.
//
// Action (20): VoteWeighting.removeNominee(bytes32 account, uint256 chainId) for each legacy
// (account, chainId) pair. VoteWeighting lives on L1 and tracks nominees for every chain via the
// chainId argument, so ALL 20 calls are DIRECT L1 Timelock calls regardless of where the staking
// contract is deployed — there are NO L2 bridge messages in this proposal.
//
// WARNING: removeNominee is IRREVERSIBLE — a removed (account, chainId) pair can never be
// re-nominated (VoteWeighting._addNominee reverts NomineeRemoved; mapRemovedNominees is never
// cleared). Re-enabling a removed program requires deploying a new contract at a new address.
//
// TIMING: removeNominee routes through Dispenser.removeNominee, which reverts Overflow if called
// within the last week of the ongoing epoch (block.timestamp >= epochEnd - 1 week). This proposal
// MUST be executed with > 7 days left in the epoch (epoch length is 14 days). removeNominee is
// owner-only and reverts NomineeDoesNotExist if a target is not a live nominee — all 20 are
// currently nominated.
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal12Builder {
    address internal constant VOTE_WEIGHTING = 0x95418b46d5566D3d1ea62C12Aea91227E566c5c1;

    // ---- chain ids ----
    uint256 internal constant CID_OPTIMISM = 10;
    uint256 internal constant CID_GNOSIS   = 100;
    uint256 internal constant CID_POLYGON  = 137;
    uint256 internal constant CID_BASE     = 8453;

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas staking nominee cleanup, part 2. This proposal removes the remaining legacy staking contract nominees from the VoteWeighting contract by calling removeNominee(bytes32,uint256) for the corresponding (account, chainId) pairs across Gnosis, Polygon, Optimism and Base. These programs have been superseded by the new staking contract generation and carry no active vote weight. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](20);
        values = new uint256[](20);
        calldatas = new bytes[](20);
        uint256 k;

        // -- Gnosis (100): Pearl Beta Mech Marketplace I..VIII (8) --
        k = _rm(targets, calldatas, k, 0xAb10188207Ea030555f53C8A84339A92f473aa5e, CID_GNOSIS); // Pearl Beta Mech Marketplace
        k = _rm(targets, calldatas, k, 0x8d7bE092d154b01d404f1aCCFA22Cef98C613B5D, CID_GNOSIS); // Pearl Beta Mech Marketplace II
        k = _rm(targets, calldatas, k, 0x9D00A0551F20979080d3762005C9B74D7Aa77b85, CID_GNOSIS); // Pearl Beta Mech Marketplace III
        k = _rm(targets, calldatas, k, 0xE2f80659dB1069f3B6a08af1A62064190c119543, CID_GNOSIS); // Pearl Beta Mech Marketplace IV
        k = _rm(targets, calldatas, k, 0x536D04dBD9A2310152a0D2d8D18daDFCA8Bb26b0, CID_GNOSIS); // Pearl Beta Mech Marketplace V
        k = _rm(targets, calldatas, k, 0xac3Ed39D18d9C951BD2e7F0024114849C0a25295, CID_GNOSIS); // Pearl Beta Mech Marketplace VI
        k = _rm(targets, calldatas, k, 0xB2303F9913f11131A74F4b05099Ced2043cc72C4, CID_GNOSIS); // Pearl Beta Mech Marketplace VII
        k = _rm(targets, calldatas, k, 0x12bdd401Ac300482f4017C64c6c930ee40424c08, CID_GNOSIS); // Pearl Beta Mech Marketplace VIII

        // -- Polygon (137): Polymarket (3) --
        k = _rm(targets, calldatas, k, 0x8887C2852986e7cbaC99B6065fFe53074A6BCC26, CID_POLYGON); // Polymarket Alpha - III
        k = _rm(targets, calldatas, k, 0x9F1936f6afB5EAaA2220032Cf5e265F2Cc9511Cc, CID_POLYGON); // Polymarket Beta - I
        k = _rm(targets, calldatas, k, 0x22D58680F643333F93205B956a4Aa1dC203a16Ad, CID_POLYGON); // Polymarket Beta - II

        // -- Optimism (10): Optimus Alpha II..IV (3) --
        k = _rm(targets, calldatas, k, 0xBCA056952D2A7a8dD4A002079219807CFDF9fd29, CID_OPTIMISM); // Optimus Alpha II
        k = _rm(targets, calldatas, k, 0x0f69f35652B1acdbD769049334f1AC580927E139, CID_OPTIMISM); // Optimus Alpha III
        k = _rm(targets, calldatas, k, 0x6891Cf116f9a3bDbD1e89413118eF81F69D298C3, CID_OPTIMISM); // Optimus Alpha IV

        // -- Base (8453): Pett.AI x2, Agents.fun x3, invalid-metadata staking contract (6) --
        k = _rm(targets, calldatas, k, 0xFA0ca3935758cB81D35A8F1395b9Eb5a596ce301, CID_BASE); // Pett.AI Agent Staking Contract
        k = _rm(targets, calldatas, k, 0x00D544c10BDC0E9b0a71CeAF52C1342BB8f21c1D, CID_BASE); // Pett.AI Agent Staking Contract 2
        k = _rm(targets, calldatas, k, 0x2585e63df7BD9De8e058884D496658a030b5c6ce, CID_BASE); // Agents.fun 1
        k = _rm(targets, calldatas, k, 0x26FA75ef9Ccaa60E58260226A71e9d07564C01bF, CID_BASE); // Agents.fun 2
        k = _rm(targets, calldatas, k, 0x4D4233EBF0473Ca8f34d105A6256A2389176F0Ce, CID_BASE); // Agents.fun 3
        k = _rm(targets, calldatas, k, 0x0dfaFbf570e9E813507aAE18aA08dFbA0aBc5139, CID_BASE); // unused staking contract with invalid metadata (0 weight, 0 services)

        require(k == 20, "length mismatch");
        description = DESCRIPTION;
    }

    /// @dev removeNominee(bytes32 account, uint256 chainId) on VoteWeighting (direct L1).
    function _rm(address[] memory targets, bytes[] memory calldatas, uint256 k, address account, uint256 chainId)
        internal pure returns (uint256)
    {
        targets[k] = VOTE_WEIGHTING;
        calldatas[k] = abi.encodeWithSignature("removeNominee(bytes32,uint256)", bytes32(uint256(uint160(account))), chainId);
        return k + 1;
    }
}

/// @notice forge script scripts/proposals/proposal_12/Proposal12Unnominate.s.sol:Proposal12Unnominate
contract Proposal12Unnominate is Script, Proposal12Builder {
    function run() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        console2.log("=== Proposal 12: un-nominate legacy staking contracts ===");
        console2.log("entries:", targets.length);
        for (uint256 i; i < targets.length; ++i) {
            console2.log("--- index", i, "---");
            console2.log("target  :", targets[i]);
            console2.log("value   :", values[i]);
            console2.logBytes(calldatas[i]);
        }
        console2.log("description:");
        console2.log(description);
        bytes32 id = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description))));
        console2.log("proposalId:");
        console2.logBytes32(id);
    }
}
