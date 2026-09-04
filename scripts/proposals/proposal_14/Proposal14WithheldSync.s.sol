// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// ============================================================================================
// PROPOSAL 14 — sync the L2 withheld OLAS amounts back to L1.
//
// Seven actions, one per chain that holds a withheld balance. Each instructs that chain's
// staking target dispenser to report its withheld OLAS amount back to the L1 Dispenser.
//
// WHAT A SYNC DOES. A target dispenser caps each staking deposit at what the target can take
// (DefaultTargetDispenserL2._processData -> verifyInstanceAndGetEmissionsAmount) and keeps the
// remainder as `withheldAmount`. syncWithheldAmount reports that figure to L1, where
// Dispenser.mapChainIdWithheldAmounts nets it against FUTURE transfers to the same chain
// (Dispenser.sol:728-740 and :1193-1207). No tokens move: the effect is that L1 stops sending
// OLAS to a chain that is already holding some, and the balance is drawn down over subsequent
// epochs.
//
// WHY NOW. The path has never been used. As of 2026-09-04 the seven dispensers hold ~5.03M OLAS
// of withheld balance between them, every L2 stakingBatchNonce reads 0, and every
// mapChainIdWithheldAmounts entry on L1 reads 0.
//
//   [0] POLYGON,  bridged via FxRoot            — 100,408.03 OLAS
//   [1] GNOSIS,   bridged via the AMB           — 2,620,457.10 OLAS
//   [2] OPTIMISM, bridged via the L1CDM         — 225,834.65 OLAS
//   [3] BASE,     bridged via the L1CDM         — 1,380,908.80 OLAS
//   [4] CELO,     bridged via the L1CDM         — 724.80 OLAS
//   [5] MODE,     bridged via the L1CDM         — 703,245.03 OLAS
//   [6] ARBITRUM, retryable ticket via the Inbox — 724.80 OLAS
//
// THE AMOUNTS ARE NOT IN THE CALLDATA. Each dispenser reads its own withheldAmount at execution
// time, so the figures above are context for voters, not parameters. They move whenever a
// distribution is claimed, and that costs this proposal nothing.
//
// ARBITRUM IS SHAPED DIFFERENTLY, and it is the one entry carrying ETH. There is no governance
// receiver contract on Arbitrum: the dispenser's owner is the L1 Timelock's L2 ALIAS
// (0x3C1fF68f…D95fE + 0x1111…1111 = 0x4d30F68F…a70F), so a retryable ticket arrives already
// authorised and calls the dispenser directly. Entry [6] therefore carries
// maxSubmissionCost + gasLimit * maxFeePerGas as `value`, paid by the Timelock from its own
// balance. maxSubmissionCost tracks the L1 base fee: REGENERATE entry [6] shortly before
// submission via Inbox.calculateRetryableSubmissionFee(dataLength, 0).
//
// TWO WIRE FORMATS, DO NOT MIX THEM.
//   - Polygon: FxChild calls processMessageFromRoot itself, so sendMessageToChild carries the
//     packed buffer DIRECTLY.
//   - Gnosis and OP-stack: the bridge calls the mediator, so the message must be the ENCODED
//     CALL processMessageFromForeign(bytes) / processMessageFromSource(bytes) wrapping the
//     packed buffer. Passing the bare packed buffer there reaches the mediator with a garbage
//     selector and reverts on the destination chain, where it is expensive to notice.
//   The packed buffer itself is the mediators' shared format:
//     target(20) | value(uint96,12) | payloadLength(uint32,4) | payload
//
// ADDRESS COLLISION WARNING — 0x9338b5153AE39BB89f50468E608eD9d764B755fD is BOTH Polygon's
// FxGovernorTunnel (entry [0] receiver) and Mode's OptimismMessenger mediator (entry [5]
// receiver), through aligned deployer nonces. Both are used in this file with different
// meanings. Each was verified by calling a chain-specific getter on the chain it is used on:
//   - Polygon 0x9338b515… : fxChild() == 0x8397259c…, rootGovernor() == TIMELOCK
//   - Mode    0x9338b515… : CDMContractProxyHome() == 0x42…07, sourceGovernor() == TIMELOCK
//
// proposalId = keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))).
// description.txt MUST match the DESCRIPTION string below byte-for-byte before submission.
// ============================================================================================
abstract contract Proposal14Builder {
    // ---- L1 ----
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant FX_ROOT = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2;
    address internal constant AMB_FOREIGN = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e;
    address internal constant OPTIMISM_L1CDM = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address internal constant BASE_L1CDM = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
    address internal constant CELO_L1CDM = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95;
    address internal constant MODE_L1CDM = 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f;
    address internal constant ARBITRUM_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;

    // ---- L2 governance receivers (the dispensers' owners) ----
    // Polygon FxGovernorTunnel. Same numeric address as Mode's mediator — see the warning above.
    address internal constant FX_TUNNEL_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address internal constant GNOSIS_MEDIATOR_L2 = 0x15bd56669F57192a97dF41A2aa8f4403e9491776;
    address internal constant OPTIMISM_MESSENGER_L2 = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c;
    address internal constant BASE_MESSENGER_L2 = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant CELO_MESSENGER_L2 = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d;
    // Mode mediator. Same numeric address as Polygon's FxGovernorTunnel — see the warning above.
    address internal constant MODE_MESSENGER_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;

    // ---- L2 staking target dispensers ----
    address internal constant POLYGON_DISPENSER_L2 = 0x17d96ba4532fe91809326092fE4D5606A7B7a0d8;
    address internal constant GNOSIS_DISPENSER_L2 = 0x5b6c538C7b2E0b44Fa8A3B7a0532EF797b07d0E9;
    address internal constant OPTIMISM_DISPENSER_L2 = 0xaea9ef993d8a1A164397642648DF43F053d43D85;
    address internal constant BASE_DISPENSER_L2 = 0x9Ec97Be9FF55ff11606ce7c589956f7Bf3D0b241;
    address internal constant CELO_DISPENSER_L2 = 0x4891f5894634DcD6d11644fe8E56756EF2681582;
    address internal constant MODE_DISPENSER_L2 = 0xEB5638eefE289691EcE01943f768EDBF96258a80;
    address internal constant ARBITRUM_DISPENSER_L2 = 0x5953f21495BD9aF1D78e87bb42AcCAA55C1e896C;

    // ---- bridge parameters ----
    // Matches CELO_MIN_GAS in proposal 11 and MODE_MIN_GAS in proposal 13 for the same shape.
    uint32 internal constant OP_MIN_GAS = 2_000_000;
    // AMB gas for the forward message. Kept well inside the bridge's per-transaction maximum.
    uint256 internal constant AMB_GAS = 2_000_000;
    // Gas limit carried in the dispenser's own bridgePayload for the RETURN (L2 -> L1) message.
    // DefaultTargetDispenserL2 clamps this to [MIN_GAS_LIMIT 300k, MAX_GAS_LIMIT 2M]; the L1 leg
    // measures ~80k, so the minimum is ample. Polygon and Arbitrum ignore the payload entirely.
    uint256 internal constant RETURN_GAS = 300_000;

    // Arbitrum retryable pricing. REGENERATE maxSubmissionCost before submission — it tracks the
    // L1 base fee. Read on 2026-09-04 from Inbox.calculateRetryableSubmissionFee(68, 0).
    uint256 internal constant ARB_MAX_SUBMISSION_COST = 809_502_808_032;
    uint256 internal constant ARB_GAS_LIMIT = 300_000;
    uint256 internal constant ARB_MAX_FEE_PER_GAS = 0.1 gwei;

    // NOTE: regenerate description.txt to match this byte-for-byte before submission.
    string internal constant DESCRIPTION =
        "Olas L2 withheld amount synchronisation. Each Olas staking target dispenser on an L2 caps a staking deposit at the amount the target can accept and retains the remainder as a withheld amount. This proposal instructs the target dispensers on Polygon, Gnosis, Optimism, Base, Celo, Mode and Arbitrum to call syncWithheldAmount, reporting those retained amounts back to the Dispenser on Ethereum. No tokens are transferred by this proposal: the reported amounts are netted against future staking incentive transfers to the same chain, so that the protocol stops sending OLAS to chains that already hold an unspent balance, and the retained balances are consumed by subsequent epochs instead. The amounts are read by each dispenser at execution time and are not parameters of this proposal. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](7);
        values = new uint256[](7);
        calldatas = new bytes[](7);

        // [0] POLYGON — FxRoot carries the packed buffer directly.
        targets[0] = FX_ROOT;
        calldatas[0] = abi.encodeWithSignature(
            "sendMessageToChild(address,bytes)", FX_TUNNEL_L2, packedFor(POLYGON_DISPENSER_L2, "")
        );

        // [1] GNOSIS — the AMB calls the mediator, so the message is the encoded call.
        targets[1] = AMB_FOREIGN;
        calldatas[1] = abi.encodeWithSignature(
            "requireToPassMessage(address,bytes,uint256)",
            GNOSIS_MEDIATOR_L2,
            abi.encodeWithSignature(
                "processMessageFromForeign(bytes)", packedFor(GNOSIS_DISPENSER_L2, abi.encode(RETURN_GAS))
            ),
            AMB_GAS
        );

        // [2..5] OP-stack — same shape, four chains.
        targets[2] = OPTIMISM_L1CDM;
        calldatas[2] = _opStack(OPTIMISM_MESSENGER_L2, OPTIMISM_DISPENSER_L2);
        targets[3] = BASE_L1CDM;
        calldatas[3] = _opStack(BASE_MESSENGER_L2, BASE_DISPENSER_L2);
        targets[4] = CELO_L1CDM;
        calldatas[4] = _opStack(CELO_MESSENGER_L2, CELO_DISPENSER_L2);
        targets[5] = MODE_L1CDM;
        calldatas[5] = _opStack(MODE_MESSENGER_L2, MODE_DISPENSER_L2);

        // [6] ARBITRUM — retryable ticket straight to the dispenser, which the aliased Timelock
        //     is already authorised to call. The only entry carrying value.
        targets[6] = ARBITRUM_INBOX;
        values[6] = arbitrumTicketValue();
        calldatas[6] = abi.encodeWithSignature(
            "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
            ARBITRUM_DISPENSER_L2,
            uint256(0),
            ARB_MAX_SUBMISSION_COST,
            TIMELOCK,
            TIMELOCK,
            ARB_GAS_LIMIT,
            ARB_MAX_FEE_PER_GAS,
            syncCalldata("")
        );

        description = DESCRIPTION;
    }

    /// @dev `syncWithheldAmount(bytes)` — the call every entry ultimately makes.
    function syncCalldata(bytes memory bridgePayload) public pure returns (bytes memory) {
        return abi.encodeWithSignature("syncWithheldAmount(bytes)", bridgePayload);
    }

    /// @dev The buffer the governance receivers unpack. Exposed so the L2 leg tests replay the
    ///      proposal's own bytes rather than a re-encoded lookalike.
    function packedFor(address dispenser, bytes memory bridgePayload) public pure returns (bytes memory) {
        bytes memory inner = syncCalldata(bridgePayload);
        return abi.encodePacked(dispenser, uint96(0), uint32(inner.length), inner);
    }

    /// @dev The ETH entry [6] carries.
    function arbitrumTicketValue() public pure returns (uint256) {
        return ARB_MAX_SUBMISSION_COST + ARB_GAS_LIMIT * ARB_MAX_FEE_PER_GAS;
    }

    function _opStack(address messengerL2, address dispenserL2) internal pure returns (bytes memory) {
        bytes memory l2call =
            abi.encodeWithSignature("processMessageFromSource(bytes)", packedFor(dispenserL2, abi.encode(RETURN_GAS)));
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", messengerL2, l2call, OP_MIN_GAS);
    }
}

/// @notice Run: forge script scripts/proposals/proposal_14/Proposal14WithheldSync.s.sol:Proposal14WithheldSync
///         (no broadcast — prints the proposal arrays to copy into the governor `propose(...)` call).
contract Proposal14WithheldSync is Script, Proposal14Builder {
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
