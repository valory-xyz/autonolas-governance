// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 15 — raise the Governor's proposal threshold and quorum.
//
// Two actions, both on the Governor itself. Both setters are `onlyGovernance`, whose executor is
// Timelock A, so a governance proposal is the only route to either.
//
//   [0] setProposalThreshold(250_000e18)  — from 5_000e18
//   [1] updateQuorumNumerator(10)         — from 3, i.e. 3% -> 10% of voting power at a snapshot
//
// WHY. A proposal created on 2026-09-05 asked the DAO to transfer Treasury ownership to an
// externally owned account. Its proposer held 5,100 OLAS, just over the 5,000 veOLAS minimum,
// which has not been revisited since deployment.
//
// THRESHOLD — 250,000 IS THE TOP OF A FLAT BAND. Live voting power is concentrated: the five
// largest positions are all above 250,000 veOLAS and the sixth is below 16,000, so every
// threshold between those two levels admits the same five addresses. Taking the top of the band
// maximises the cost of an attempt without excluding anyone that a lower level inside the band
// would admit. It is still a real restriction against TODAY's setting: twelve addresses clear
// 5,000, five clear 250,000, and holders in between regain eligibility by increasing or
// extending a lock.
//
// THE CAP THAT MATTERS. `GovernorCompatibilityBravo.cancel` is permissionless once the
// PROPOSER's power sits below `proposalThreshold()`. A threshold above the power of the address
// that creates the DAO's proposals would make the DAO's own live proposals cancellable by
// anyone, so 250,000 is deliberately kept below it. Re-check that before execution — veOLAS
// power decays continuously.
//
// QUORUM — WHY 10. Bravo counts only For votes toward quorum (`COUNTING_MODE()` is
// `support=bravo&quorum=bravo`, `_quorumReached` is `quorum(snapshot) <= forVotes`), so quorum
// is the floor an UNOPPOSED proposal must reach; the threshold is only the entry fee. Every
// proposal in this Governor's history was carried by a single voter fielding between 286,101 and
// 1,126,974 votes, and at a 10% numerator each of the four largest positions still clears quorum
// on its own. 15% would need two voters to coordinate, which has never happened.
//
// NOTHING IN FLIGHT IS AFFECTED. `quorum(blockNumber)` reads `quorumNumerator(blockNumber)` from
// a checkpoint history, so proposals already snapshotted keep the 3% bar. The new numerator
// binds at the execution block, since the checkpoint is written with key `block.number` and the
// lookup is inclusive.
//
// WHAT THIS IS NOT. Neither change defends the Treasury against a funded proposer. Both raise
// the cost of putting a proposal in front of the DAO that it must then mobilise to defeat.
// ============================================================================================

contract Proposal15GovernorParams is Script {
    address internal constant GOVERNOR = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6;

    uint256 internal constant NEW_PROPOSAL_THRESHOLD = 250_000e18;
    uint256 internal constant NEW_QUORUM_NUMERATOR = 10;

    function buildProposal()
        public
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        targets = new address[](2);
        values = new uint256[](2);
        calldatas = new bytes[](2);

        targets[0] = GOVERNOR;
        calldatas[0] = abi.encodeWithSignature("setProposalThreshold(uint256)", NEW_PROPOSAL_THRESHOLD);

        targets[1] = GOVERNOR;
        calldatas[1] = abi.encodeWithSignature("updateQuorumNumerator(uint256)", NEW_QUORUM_NUMERATOR);

        description = string(
            abi.encodePacked(
                "Raise the Olas Governor proposal threshold and quorum. This proposal sets proposalThreshold",
                " from 5,000e18 to 250,000e18 and the quorum numerator from 3 to 10. The proposal minimum has",
                " not been revisited since deployment. Raising it restricts proposal creation from twelve",
                " addresses to five at current voting power; holders below the new level regain it by",
                " increasing or extending a lock. The quorum numerator is checkpointed, so proposals already",
                " snapshotted keep the 3% bar. In accordance with Autonolas DAO Constitution at",
                " ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u"
            )
        );
    }

    function run() external pure {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();

        console2.log("targets / values / calldatas (%s entries)", targets.length);
        for (uint256 i = 0; i < targets.length; ++i) {
            console2.log("--- entry %s ---", i);
            console2.log("target  ", targets[i]);
            console2.log("value   ", values[i]);
            console2.logBytes(calldatas[i]);
        }
        console2.log("description:");
        console2.log(description);
        console2.log("descriptionHash:");
        console2.logBytes32(keccak256(bytes(description)));
        console2.log("proposalId:");
        console2.logBytes32(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))));
        console2.log("proposalId (uint):");
        console2.log(uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description))))));
    }
}
