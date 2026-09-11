// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 16 — bring Robinhood Chain (4663) into the protocol's governed surface.
//
// Wave 1 deployed and handed over every Olas contract on 4663: 28 contracts, all verified on
// Sourcify, and on 2026-09-11 all ten owner-bearing ones were transferred to the chain's
// governance control point. Nothing on 4663 answers to the deployer EOA any more. What is
// still missing is the L1 side: the Dispenser does not know the chain exists, and GuardCM
// holds no route for it, so community-multisig transactions to 4663 fail closed exactly as
// Mode's did before proposal 13.
//
// Three actions, all direct L1 Timelock calls. Unlike proposal 13, none carries a bridged
// payload — every target is on mainnet.
//
//   [0] Dispenser.setDepositProcessorChainIds — register the 4663 deposit processor, so staking
//       incentives can be claimed for 4663 nominees. Until this lands,
//       mapChainIdDepositProcessors(4663) == address(0) and any claim for a 4663 nominee
//       reverts.
//
//   [1] GuardCM.setBridgeMediatorL1BridgeParams — register the 4663 route. Robinhood Chain is
//       an Arbitrum Orbit rollup, so it reuses the same ProcessBridgedDataArbitrum verifier as
//       Arbitrum One, entered against its own Delayed Inbox.
//
//   [2] GuardCM.setTargetSelectorChainIds — allowlist the four triples 4663 needs to match the
//       rest of the fleet: pause() on ServiceManagerProxy and ArbitrumTargetDispenserL2, and
//       drain() / drain(address) on the two service registries.
//
// PARITY IS THE RULE FOR ENTRY 2, AND IT IS LOAD-BEARING. The selector set was taken from what
// GuardCM actually holds for the other chains, not from what looked reasonable:
//   - pause() is true on every chain for both the service manager proxy and the L2 dispenser;
//   - unpause() is FALSE on every chain for both. It is deliberately excluded here. Granting it
//     would let the community multisig lift a pause on 4663 in a single transaction with no
//     vote — the CM holds the Timelock's PROPOSER_ROLE and EXECUTOR_ROLE, getMinDelay() is 0,
//     and GuardCM is the CM Safe's guard, so this allowlist is the only constraint. An earlier
//     revision of this proposal included unpause() and was caught in review;
//   - drain() (0x9890220b) on ServiceRegistryL2 and drain(address) (0xece53132) on
//     ServiceRegistryTokenUtility are true on every chain, set by proposal 11. Without them 4663
//     would be the only chain where draining slashed funds needs a full governance cycle.
//
// ENTRIES 1 AND 2 MUST SHIP TOGETHER. Mode is the cautionary case: its allowlist entries were
// backfilled in July 2026 but setBridgeMediatorL1BridgeParams was never called, leaving
// verifierL2 == 0 and every CM transaction to Mode failing closed for two months until
// proposal 13 repaired it. An allowlist without bridge params is not a partial capability, it
// is none.
//
// ADDRESS COLLISION WARNING — read before editing any constant below.
//   - ROBINHOOD_MEDIATOR_L2 (0x4d30F68F…) is byte-identical to Arbitrum One's mediator. This is
//     correct and load-bearing, not a copy-paste error: on every Orbit chain the L2 governance
//     sender is alias(L1 Timelock) = TIMELOCK + 0x1111…1111 (mod 2^160), and the aliasing rule
//     is chain-independent. Both chains alias the same L1 Timelock, so both yield the same
//     address. Verified on chain: the same address holds nonce 12 on Arbitrum One, i.e. the DAO
//     has already driven it there twelve times, and on 4663 it is the owner() of all ten
//     handed-over contracts.
//   - VERIFIER_ARBITRUM (0x0F336366…) is likewise shared with the Arbitrum One route by design:
//     one verifier contract serves every Orbit chain. Reading GuardCM's existing Arbitrum entry
//     returns exactly this verifier and exactly this mediator; only the inbox and chain Id differ.
//   - ROBINHOOD_SERVICE_MANAGER_PROXY (0x63e66d7a…) and ROBINHOOD_TARGET_DISPENSER_L2
//     (0xc40C79C2…) are 4663 addresses used only as GuardCM allowlist keys. They are never
//     called from L1 by this proposal.
//
// DISTINCTNESS CHECK. Every constant below that could plausibly be confused with an Arbitrum One
// equivalent was verified against the chain it belongs to:
//   - ROBINHOOD_INBOX      : bridge().rollup() resolves to the 4663 rollup, and the L1 gateway
//                            whose counterpart minted OLAS on 4663 returns this address from
//                            inbox()                                  -> it is 4663's inbox
//   - ROBINHOOD_PROCESSOR  : l2TargetChainId() == 4663                 -> it is 4663's processor
//   - ROBINHOOD_TARGET_DISPENSER_L2 : owner() == ROBINHOOD_MEDIATOR_L2 on 4663, and
//                            l2MessageRelayer() == ArbSys              -> it is 4663's dispenser
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal16Builder {
    // ---- L1 ----
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant GUARD_CM = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;
    address internal constant DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;

    // Robinhood Chain Delayed Inbox — the L1 entrypoint for 4663, and GuardCM's mapping key.
    address internal constant ROBINHOOD_INBOX = 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D;
    // Orbit bridge-data verifier, shared with the Arbitrum One route by design — see the warning.
    address internal constant VERIFIER_ARBITRUM = 0x0F33636698F6607B2FDdC1e857788535914C44d4;
    // L1 deposit processor for 4663. l2TargetChainId() == 4663.
    address internal constant ROBINHOOD_PROCESSOR_L1 = 0xb9DfcC6155Ba4F211DCf8e6eCc9976Be11bB7a77;

    // ---- Robinhood Chain (4663) ----
    // alias(TIMELOCK). Same numeric address as Arbitrum One's mediator — see the warning above.
    address internal constant ROBINHOOD_MEDIATOR_L2 = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F;
    address internal constant ROBINHOOD_SERVICE_MANAGER_PROXY = 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b;
    address internal constant ROBINHOOD_TARGET_DISPENSER_L2 = 0xc40C79C275F3fA1F3f4c723755C81ED2D53A8D81;
    address internal constant ROBINHOOD_SERVICE_REGISTRY_L2 = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant ROBINHOOD_SERVICE_REGISTRY_TOKEN_UTILITY = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;

    uint256 internal constant CID_ROBINHOOD = 4663;

    bytes4 internal constant SELECTOR_PAUSE = 0x8456cb59; // pause()
    bytes4 internal constant SELECTOR_DRAIN = 0x9890220b; // drain()
    bytes4 internal constant SELECTOR_DRAIN_TOKEN = 0xece53132; // drain(address)
    // unpause() = 0x3f4ba83a is deliberately NOT allowlisted — see the parity note in the header.

    string internal constant DESCRIPTION =
        "Olas on Robinhood Chain: wave 2. Wave 1 deployed the full Olas stack on Robinhood Chain (chain Id 4663) and transferred ownership of every owner-bearing contract to the chain's governance control point, so the DAO already controls the deployment. This proposal connects the L1 side. It (1) registers the Robinhood Chain deposit processor with the Dispenser, so that staking incentives can be claimed for nominees on that chain; (2) registers the Robinhood Chain bridge route in the GuardCM community multisig guard by calling setBridgeMediatorL1BridgeParams, so that community multisig transactions to Robinhood Chain are verified the same way as those to Arbitrum One, which uses the same Orbit bridge-data verifier; and (3) allowlists in GuardCM exactly the selector set the community multisig already holds on the other chains: the pause selector for the Robinhood Chain service manager proxy and target dispenser, and the drain selectors for the Robinhood Chain service registry and service registry token utility. The unpause selector is deliberately excluded, because it is allowlisted on no other chain. Entries (2) and (3) are submitted together deliberately: an allowlist without bridge parameters leaves community multisig transactions failing closed, as was the case for Mode until proposal 13. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](3);
        values = new uint256[](3);
        calldatas = new bytes[](3);

        // [0] MAINNET — register the 4663 deposit processor with the Dispenser.
        targets[0] = DISPENSER;
        calldatas[0] = _dispenserRegisterProcessor();

        // [1] MAINNET — register the 4663 bridge route in GuardCM.
        targets[1] = GUARD_CM;
        calldatas[1] = _guardCmRobinhoodRoute();

        // [2] MAINNET — allowlist the four pause/unpause triples for 4663 in GuardCM.
        targets[2] = GUARD_CM;
        calldatas[2] = _guardCmRobinhoodSelectors();

        description = DESCRIPTION;
    }

    /// @dev Dispenser.setDepositProcessorChainIds for the single 4663 route.
    function _dispenserRegisterProcessor() internal pure returns (bytes memory) {
        address[] memory procs = new address[](1);
        procs[0] = ROBINHOOD_PROCESSOR_L1;
        uint256[] memory cids = new uint256[](1);
        cids[0] = CID_ROBINHOOD;
        return abi.encodeWithSignature("setDepositProcessorChainIds(address[],uint256[])", procs, cids);
    }

    /// @dev GuardCM.setBridgeMediatorL1BridgeParams for the single 4663 route.
    function _guardCmRobinhoodRoute() internal pure returns (bytes memory) {
        address[] memory l1s = new address[](1);
        l1s[0] = ROBINHOOD_INBOX;
        address[] memory vs = new address[](1);
        vs[0] = VERIFIER_ARBITRUM;
        uint256[] memory cids = new uint256[](1);
        cids[0] = CID_ROBINHOOD;
        address[] memory l2s = new address[](1);
        l2s[0] = ROBINHOOD_MEDIATOR_L2;
        return abi.encodeWithSignature(
            "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])", l1s, vs, cids, l2s
        );
    }

    /// @dev GuardCM.setTargetSelectorChainIds — four triples, all enabled, all on 4663.
    ///      Exactly the set the other chains hold: pause() on the two pausable contracts, and the
    ///      two drain selectors on the two registries. unpause() is excluded on purpose.
    function _guardCmRobinhoodSelectors() internal pure returns (bytes memory) {
        address[] memory targets_ = new address[](4);
        targets_[0] = ROBINHOOD_SERVICE_MANAGER_PROXY;
        targets_[1] = ROBINHOOD_TARGET_DISPENSER_L2;
        targets_[2] = ROBINHOOD_SERVICE_REGISTRY_L2;
        targets_[3] = ROBINHOOD_SERVICE_REGISTRY_TOKEN_UTILITY;

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SELECTOR_PAUSE;
        selectors[1] = SELECTOR_PAUSE;
        selectors[2] = SELECTOR_DRAIN;
        selectors[3] = SELECTOR_DRAIN_TOKEN;

        uint256[] memory cids = new uint256[](4);
        bool[] memory statuses = new bool[](4);
        for (uint256 i = 0; i < 4; ++i) {
            cids[i] = CID_ROBINHOOD;
            statuses[i] = true;
        }

        return abi.encodeWithSignature(
            "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])", targets_, selectors, cids, statuses
        );
    }
}

/// @notice Run: forge script scripts/proposals/proposal_16/Proposal16Robinhood.s.sol:Proposal16Robinhood
///         (no broadcast — prints the proposal arrays to copy into the governor `propose(...)` call).
contract Proposal16Robinhood is Script, Proposal16Builder {
    function run() external pure {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = buildProposal();

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
