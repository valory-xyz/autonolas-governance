// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Proposal14Builder} from "../../scripts/proposals/proposal_14/Proposal14WithheldSync.s.sol";

// Minimal OZ-Governor surface (GovernorOLAS).
interface IGovernor {
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        external
        returns (uint256);
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function proposalEta(uint256 proposalId) external view returns (uint256);
}

interface IDispenserL1 {
    function mapChainIdWithheldAmounts(uint256 chainId) external view returns (uint256);
    function mapChainIdDepositProcessors(uint256 chainId) external view returns (address);
}

/// @notice L1 validation for proposal 14 on a MAINNET fork, through the CURRENTLY-LIVE GovernorOLAS.
///
///         Every entry is bridged, so nothing in this proposal has a directly observable L1 state
///         effect: what L1 can show is that each bridge entrypoint accepts the call and emits the
///         outbound message. The destination-chain effect — the dispenser actually syncing — is
///         covered per chain in Proposal14L2Legs.t.sol.
///
///         Run: ETH_RPC=<mainnet rpc> forge test --match-contract Proposal14WithheldSyncTest -vvv
contract Proposal14WithheldSyncTest is Test, Proposal14Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant L1_DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;
    address internal constant FX_STATE_SENDER = 0x28e4F3a7f651294B9564800b2D01f35189A5bFbE;
    address internal constant FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    bytes32 internal constant SENT_MESSAGE_TOPIC = keccak256("SentMessage(address,address,bytes,uint256,uint256)");
    bytes32 internal constant STATE_SYNCED_TOPIC = keccak256("StateSynced(uint256,address,bytes)");
    bytes32 internal constant AFFIRMATION_TOPIC = keccak256("UserRequestForAffirmation(bytes32,bytes)");
    bytes32 internal constant INBOX_MESSAGE_TOPIC = keccak256("InboxMessageDelivered(uint256,bytes)");

    function _fork() internal {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
    }

    function _mockVotes() internal {
        vm.mockCall(
            WVEOLAS,
            abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))),
            abi.encode(uint256(1e28))
        );
        vm.mockCall(
            WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28))
        );
        vm.mockCall(
            WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24))
        );
    }

    /// @dev Nothing has ever been synced, and every route this proposal uses exists. The deposit
    ///      processors are the positive control: a zero withheld amount next to a zero processor
    ///      would just mean the chain is unconfigured.
    function test_preconditions() public {
        _fork();
        IDispenserL1 disp = IDispenserL1(L1_DISPENSER);
        uint256[7] memory chains = [uint256(137), 100, 10, 8453, 42220, 34443, 42161];
        for (uint256 i; i < chains.length; ++i) {
            assertTrue(disp.mapChainIdDepositProcessors(chains[i]) != address(0), "chain has no deposit processor");
            assertEq(disp.mapChainIdWithheldAmounts(chains[i]), 0, "chain already carries a withheld credit");
        }

        (address[] memory targets,,,) = buildProposal();
        for (uint256 i; i < targets.length; ++i) {
            assertGt(targets[i].code.length, 0, "bridge entrypoint has no code");
        }

        // Entry [6] is the only one carrying ETH, and the Timelock pays it from its own balance —
        // so no top-up is a prerequisite for this vote and no ETH need be attached at execution.
        console2.log("Timelock balance   ", TIMELOCK.balance);
        console2.log("Arbitrum ticket cost", arbitrumTicketValue());
        assertGe(TIMELOCK.balance, arbitrumTicketValue(), "Timelock cannot fund the Arbitrum ticket");
    }

    function test_L1_fullGovernanceLifecycle() public {
        _fork();
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 dh = keccak256(bytes(description));
        IGovernor gov = IGovernor(NEW_GOV);

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");

        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        console2.log("proposed id:", id);

        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);

        vm.recordLogs();
        uint256 g = gasleft();
        // No value is attached: the Arbitrum ticket is paid out of the Timelock's own balance.
        gov.execute(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertAllSevenDispatched(vm.getRecordedLogs());

        console2.log("Governor.execute() gas used:", executeGas);
        console2.log("EIP-7825 per-tx cap:        ", uint256(16777216));
        assertLt(executeGas, 16777216, "execute exceeds EIP-7825 per-tx gas cap");
    }

    /// @dev Every entry must be observed handing ITS OWN payload to ITS OWN bridge. Counting
    ///      dispatches is not enough: four entries share an event signature, so a count passes with
    ///      two entries pointed at the same messenger, and a bare bool passes on any AMB or Inbox
    ///      traffic in the block. Each assertion below is therefore matched against the bytes the
    ///      builder produced for that entry.
    function _assertAllSevenDispatched(Vm.Log[] memory logs) internal {
        (address[] memory targets,, bytes[] memory calldatas,) = buildProposal();

        // [0] Polygon — the synced payload must be the packed buffer this proposal built.
        (address tunnel, bytes memory packed) = abi.decode(_stripSelector(calldatas[0]), (address, bytes));
        assertTrue(_sawPolygon(logs, tunnel, packed), "Polygon message not dispatched with the proposal's buffer");

        // [1] Gnosis — the AMB re-encodes with its own header, so assert containment.
        (, bytes memory gnosisMsg,) = abi.decode(_stripSelector(calldatas[1]), (address, bytes, uint256));
        assertTrue(_sawContaining(logs, AMB_FOREIGN, AFFIRMATION_TOPIC, gnosisMsg), "Gnosis message not dispatched");

        // [2..5] OP-stack — matched per entry on (emitter, target, message), so a mispaired
        // (L1 messenger, L2 receiver) survives nothing.
        for (uint256 i = 2; i <= 5; ++i) {
            (address receiver, bytes memory message,) =
                abi.decode(_stripSelector(calldatas[i]), (address, bytes, uint32));
            assertTrue(_sawOpMessage(logs, targets[i], receiver, message), "OP-stack entry not dispatched as built");
        }

        // [6] Arbitrum — the Inbox re-encodes the ticket, so assert the L2 calldata is in it.
        (,,,,,,, bytes memory arbData) = abi.decode(
            _stripSelector(calldatas[6]), (address, uint256, uint256, address, address, uint256, uint256, bytes)
        );
        assertTrue(_sawContaining(logs, ARBITRUM_INBOX, INBOX_MESSAGE_TOPIC, arbData), "Arbitrum retryable not created");
    }

    function _sawPolygon(Vm.Log[] memory logs, address tunnel, bytes memory packed) internal pure returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != FX_STATE_SENDER || logs[i].topics[0] != STATE_SYNCED_TOPIC) continue;
            if (address(uint160(uint256(logs[i].topics[2]))) != FX_CHILD) continue;
            (address rootSender, address receiver, bytes memory payload) =
                abi.decode(abi.decode(logs[i].data, (bytes)), (address, address, bytes));
            if (rootSender == TIMELOCK && receiver == tunnel && keccak256(payload) == keccak256(packed)) return true;
        }
        return false;
    }

    function _sawOpMessage(Vm.Log[] memory logs, address messenger, address receiver, bytes memory message)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != messenger || logs[i].topics[0] != SENT_MESSAGE_TOPIC) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != receiver) continue;
            (, bytes memory sent,,) = abi.decode(logs[i].data, (address, bytes, uint256, uint256));
            if (keccak256(sent) == keccak256(message)) return true;
        }
        return false;
    }

    /// @dev For bridges that wrap our bytes in their own envelope: find the event and require our
    ///      payload to appear inside it verbatim.
    function _sawContaining(Vm.Log[] memory logs, address emitter, bytes32 topic0, bytes memory needle)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != emitter || logs[i].topics[0] != topic0) continue;
            if (_contains(logs[i].data, needle)) return true;
        }
        return false;
    }

    function _contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0 || needle.length > haystack.length) return false;
        for (uint256 i; i <= haystack.length - needle.length; ++i) {
            bool same = true;
            for (uint256 j; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    same = false;
                    break;
                }
            }
            if (same) return true;
        }
        return false;
    }

    /// @dev Fast path: the same batch executed directly as the Timelock, which is what the
    ///      Timelock does on the governor's behalf.
    function test_L1_fullProposal_executesAsTimelock() public {
        _fork();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();
        for (uint256 i; i < targets.length; ++i) {
            vm.prank(TIMELOCK);
            (bool ok,) = targets[i].call{value: values[i]}(calldatas[i]);
            assertTrue(ok, "entry reverted");
        }
    }

    /// @notice The base-fee buffer, which is the difference between a proposal that executes and one
    ///         that reverts days after the vote. The Inbox recomputes the submission fee at execution
    ///         as 1808 * block.basefee for this payload and reverts if maxSubmissionCost is short —
    ///         and because entry [6] is in the same batch, that failure takes ALL SEVEN entries down.
    ///
    ///         Asserted from both sides so the ceiling is a fact rather than a comment: the entry
    ///         still executes at the ceiling, and stops executing above it.
    function test_arbitrumEntrySurvivesABaseFeeSpike() public {
        _fork();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();

        console2.log("base fee at fork     ", block.basefee);
        console2.log("ceiling priced for   ", ARB_BASEFEE_CEILING);
        console2.log("entry [6] value      ", values[6]);
        assertGe(TIMELOCK.balance, values[6], "Timelock cannot fund the priced ceiling");

        // At the ceiling: still executes.
        vm.fee(ARB_BASEFEE_CEILING);
        uint256 snap = vm.snapshotState();
        vm.prank(TIMELOCK);
        (bool okAtCeiling,) = targets[6].call{value: values[6]}(calldatas[6]);
        assertTrue(okAtCeiling, "entry [6] reverts at its own priced ceiling");
        vm.revertToState(snap);

        // Just above it: the Inbox rejects the submission cost. This is what the buffer buys.
        vm.fee(ARB_BASEFEE_CEILING + 1 gwei);
        vm.prank(TIMELOCK);
        (bool okAbove,) = targets[6].call{value: values[6]}(calldatas[6]);
        assertFalse(okAbove, "ceiling is not where the pricing says it is");
    }

    /// @notice Refunds must not be sent to the Timelock's own address on Arbitrum: that address
    ///         belongs to nobody there, so ETH sent to it is lost. Both refund addresses must be
    ///         the alias, which this same governance route can spend.
    function test_arbitrumRefundsGoToTheAlias() public view {
        (,, bytes[] memory calldatas,) = buildProposal();
        (,,, address excessFeeRefund, address callValueRefund,,,) = abi.decode(
            _stripSelector(calldatas[6]), (address, uint256, uint256, address, address, uint256, uint256, bytes)
        );
        address alias_ = address(uint160(TIMELOCK) + uint160(0x1111000000000000000000000000000000001111));
        assertEq(excessFeeRefund, alias_, "excessFeeRefundAddress is not the alias");
        assertEq(callValueRefund, alias_, "callValueRefundAddress is not the alias");
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(data.length - 4);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[i + 4];
        }
    }

    /// @dev Pins the description and the id derived from it, so a drifted description cannot be
    ///      submitted by accident against a reviewed id.
    function test_proposalIdMatchesCommittedDescription() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 dh = keccak256(bytes(description));
        assertEq(dh, 0x993cbb52a409a856560c105510540d773c41589ee5a5b2e46247e5c66801f9ee, "descriptionHash drifted");
        assertEq(
            keccak256(abi.encode(targets, values, calldatas, dh)),
            0x58b6db8a26f1f4bce2e9e454d299b4e0274d3f7186e0e58e695e4326f5f22ed1,
            "proposalId drifted"
        );
    }

    /// @dev The pin above only checks the builder against itself. This checks the files the HTML and
    ///      the on-chain submission are actually made from.
    function test_committedArtifactsMatchTheBuilder() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();

        string memory onDisk = vm.readFile("scripts/proposals/proposal_14/description.txt");
        assertEq(
            keccak256(bytes(onDisk)), keccak256(bytes(description)), "description.txt has drifted from the builder"
        );

        string memory json = vm.readFile("scripts/proposals/proposal_14/calldata.json");
        assertTrue(
            vm.keyExistsJson(json, string.concat("$[", vm.toString(targets.length - 1), "]")),
            "calldata.json has fewer entries than the builder"
        );
        assertFalse(
            vm.keyExistsJson(json, string.concat("$[", vm.toString(targets.length), "]")),
            "calldata.json has more entries than the builder"
        );

        for (uint256 i; i < targets.length; ++i) {
            string memory ix = vm.toString(i);
            assertEq(vm.parseJsonBytes(json, string.concat("$[", ix, "].calldata")), calldatas[i], "calldata drifted");
            assertEq(vm.parseJsonAddress(json, string.concat("$[", ix, "].target")), targets[i], "target drifted");
            assertEq(
                vm.parseJsonString(json, string.concat("$[", ix, "].value")), vm.toString(values[i]), "value drifted"
            );
            assertEq(vm.parseJsonUint(json, string.concat("$[", ix, "].index")), i, "index not in builder order");
        }
    }
}
