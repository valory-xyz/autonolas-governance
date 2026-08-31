// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 13 — cross-chain housekeeping: Mode bridge route, Mode staking allowlist, PolySafe
// retirement on Polygon.
//
// Three actions, all submitted as L1 Timelock calls; two of them carry a bridged payload.
//
//   [0] MAINNET, direct.  GuardCM.setBridgeMediatorL1BridgeParams — register the Mode (34443)
//       route. Proposal 11 configured Polygon, Gnosis, Arbitrum, Optimism, Base and Celo but
//       never Mode, so GuardCM currently holds verifierL2 == address(0) for the Mode L1
//       messenger and every community-multisig transaction to Mode fails closed. Mode is an
//       OP-stack chain and reuses the same ProcessBridgedDataOptimism verifier as Optimism,
//       Base and Celo.
//
//   [1] MODE, bridged via the Mode L1CrossDomainMessenger.  StakingVerifier
//       .setImplementationsStatuses — drop a superseded V1 staking implementation from the
//       allowlist. Nothing is unwound: the Mode StakingFactory has emitted 7 InstanceCreated
//       events, all against a different implementation, and 0 against this one.
//
//   [2] POLYGON, bridged via FxRoot.  ServiceRegistryL2.changeMultisigPermission — remove the
//       PolySafe creator from the whitelisted multisig implementations, retiring the PolySafe
//       deployment path. GnosisSafeMultisig remains whitelisted and is the fallback for any
//       service that would otherwise have deployed a PolySafe.
//
// ADDRESS COLLISION WARNING — read before editing any constant below. Three distinct contracts
// in this file share the numeric address 0x9338b5153AE39BB89f50468E608eD9d764B755fD through
// aligned deployer nonces: Polygon's FxGovernorTunnel, Mode's OptimismMessenger mediator, and
// (not used here) Gnosis's ServiceRegistryL2. Likewise 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c
// is BOTH Optimism's L2 messenger and Mode's StakingVerifier. A constant that looks correct on
// review can therefore be pointed at the wrong chain's contract. Each was verified by calling a
// chain-specific getter on the chain it is used on:
//   - Mode 0x9338b515… : CDMContractProxyHome() == 0x4200000000000000000000000000000000000007
//                        and sourceGovernor() == TIMELOCK          -> it is the Mode mediator
//   - Mode 0x87c511c8… : implementationsCheck() == true, owner() == the Mode mediator
//                        -> it is the Mode StakingVerifier
//
// setCheck WARNING: StakingVerifier.setImplementationsStatuses assigns
// `implementationsCheck = setCheck` UNCONDITIONALLY. The third argument MUST be `true` here —
// passing `false` would switch the allowlist off entirely and make verifyImplementation()
// return true for every implementation, which is the opposite of this proposal's intent.
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before on-chain submission.
// ============================================================================================
abstract contract Proposal13Builder {
    // ---- L1 ----
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant GUARD_CM = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;
    address internal constant FX_ROOT = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2;
    address internal constant MODE_L1CDM = 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f;

    // Shared OP-stack bridge verifier (already used for Optimism, Base and Celo).
    address internal constant VERIFIER_OPTIMISM = 0xdCAFcCcC7bA0b7185A472d9d068FDe0AF4313Fb5;

    // ---- L2 ----
    // Mode mediator. Same numeric address as Polygon's FxGovernorTunnel — see the warning above.
    address internal constant MODE_MESSENGER_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    // Polygon governor tunnel. Same numeric address as the Mode mediator — see the warning above.
    address internal constant FX_TUNNEL_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;

    // Mode StakingVerifier. Same numeric address as Optimism's L2 messenger — see the warning above.
    address internal constant MODE_STAKING_VERIFIER = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c;
    // Superseded V1 staking implementation on Mode; 0 proxies created against it.
    address internal constant MODE_V1_IMPLEMENTATION = 0x88DE734655184a09B70700aE4F72364d1ad23728;

    address internal constant POLYGON_SERVICE_REGISTRY_L2 = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant POLYSAFE_CREATOR = 0xA749f605D93B3efcc207C54270d83C6E8fa70fF8;

    // ---- chain ids ----
    uint256 internal constant CID_MODE = 34443;

    // Matches CELO_MIN_GAS used by proposal 11 for the same OP-stack sendMessage shape.
    uint32 internal constant MODE_MIN_GAS = 2_000_000;

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas cross-chain housekeeping. This proposal (1) registers the Mode bridge route in the GuardCM community multisig guard by calling setBridgeMediatorL1BridgeParams, so that community multisig transactions to Mode are verified the same way as those to Optimism, Base and Celo; (2) removes a superseded V1 staking implementation from the Mode StakingVerifier allowlist, where it is unused, as no staking proxy has ever been created against it; and (3) removes the PolySafe creator from the whitelisted multisig implementations of the Polygon service registry, retiring the PolySafe deployment path in favour of the standard Safe creator, which remains whitelisted. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](3);
        values = new uint256[](3);
        calldatas = new bytes[](3);

        // [0] MAINNET — register the Mode route in GuardCM.
        targets[0] = GUARD_CM;
        calldatas[0] = _guardCmModeRoute();

        // [1] MODE (bridged) — de-allowlist the superseded V1 staking implementation.
        targets[1] = MODE_L1CDM;
        calldatas[1] = _modeStakingAllowlist();

        // [2] POLYGON (bridged) — retire the PolySafe creator.
        targets[2] = FX_ROOT;
        calldatas[2] = _polygonRetirePolySafe();

        description = DESCRIPTION;
    }

    /// @dev GuardCM.setBridgeMediatorL1BridgeParams for the single Mode route.
    function _guardCmModeRoute() internal pure returns (bytes memory) {
        address[] memory l1s = new address[](1);
        l1s[0] = MODE_L1CDM;
        address[] memory vs = new address[](1);
        vs[0] = VERIFIER_OPTIMISM;
        uint256[] memory cids = new uint256[](1);
        cids[0] = CID_MODE;
        address[] memory l2s = new address[](1);
        l2s[0] = MODE_MESSENGER_L2;
        return abi.encodeWithSignature(
            "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])", l1s, vs, cids, l2s
        );
    }

    /// @dev The exact buffer the Mode mediator will unpack. Exposed so the Mode-leg fork test
    ///      replays the proposal's own bytes rather than a re-encoded lookalike.
    function modeBridgePayload() public pure returns (bytes memory) {
        address[] memory impls = new address[](1);
        impls[0] = MODE_V1_IMPLEMENTATION;
        bool[] memory statuses = new bool[](1);
        statuses[0] = false;
        // setCheck MUST stay true — it is assigned unconditionally. See the header warning.
        bytes memory inner =
            abi.encodeWithSignature("setImplementationsStatuses(address[],bool[],bool)", impls, statuses, true);
        // BridgeMessenger packing: target(20) | value(uint96,12) | payloadLength(uint32,4) | payload
        return abi.encodePacked(MODE_STAKING_VERIFIER, uint96(0), uint32(inner.length), inner);
    }

    /// @dev Mode StakingVerifier.setImplementationsStatuses, wrapped for the OP-stack bridge.
    function _modeStakingAllowlist() internal pure returns (bytes memory) {
        bytes memory l2call = abi.encodeWithSignature("processMessageFromSource(bytes)", modeBridgePayload());
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", MODE_MESSENGER_L2, l2call, MODE_MIN_GAS);
    }

    /// @dev Polygon ServiceRegistryL2.changeMultisigPermission, wrapped for the FxPortal bridge.
    ///      FxGovernorTunnel consumes the packed buffer directly — there is no processMessage
    ///      wrapper on this route, because FxChild calls processMessageFromRoot itself.
    function _polygonRetirePolySafe() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("sendMessageToChild(address,bytes)", FX_TUNNEL_L2, polygonBridgePayload());
    }

    /// @dev The exact buffer the Polygon tunnel will unpack. Exposed for the Polygon-leg fork test
    ///      and for the Tenderly simulation input.
    function polygonBridgePayload() public pure returns (bytes memory) {
        bytes memory inner =
            abi.encodeWithSignature("changeMultisigPermission(address,bool)", POLYSAFE_CREATOR, false);
        return abi.encodePacked(POLYGON_SERVICE_REGISTRY_L2, uint96(0), uint32(inner.length), inner);
    }
}

/// @notice Run: forge script scripts/proposals/proposal_13/Proposal13Housekeeping.s.sol:Proposal13Housekeeping
///         (no broadcast — prints the proposal arrays to copy into the governor `propose(...)` call).
contract Proposal13Housekeeping is Script, Proposal13Builder {
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
