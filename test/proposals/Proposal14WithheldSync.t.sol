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

    /// @dev Every entry must be observed handing its payload to its bridge. Counting is what makes
    ///      this meaningful: four OP-stack entries share an event signature, so asserting "a
    ///      SentMessage was seen" would pass with three of them silently missing.
    function _assertAllSevenDispatched(Vm.Log[] memory logs) internal view {
        uint256 opCount;
        bool sawPolygon;
        bool sawGnosis;
        bool sawArbitrum;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            address from = logs[i].emitter;
            if (
                t0 == SENT_MESSAGE_TOPIC
                    && (from == OPTIMISM_L1CDM || from == BASE_L1CDM || from == CELO_L1CDM || from == MODE_L1CDM)
            ) {
                opCount++;
            } else if (t0 == STATE_SYNCED_TOPIC && from == FX_STATE_SENDER) {
                assertEq(address(uint160(uint256(logs[i].topics[2]))), FX_CHILD, "StateSynced not addressed to FxChild");
                (address rootSender, address receiver,) =
                    abi.decode(abi.decode(logs[i].data, (bytes)), (address, address, bytes));
                assertEq(rootSender, TIMELOCK, "Polygon message not sent by the Timelock");
                assertEq(receiver, FX_TUNNEL_L2, "Polygon message wrong receiver");
                sawPolygon = true;
            } else if (t0 == AFFIRMATION_TOPIC && from == AMB_FOREIGN) {
                sawGnosis = true;
            } else if (t0 == INBOX_MESSAGE_TOPIC) {
                sawArbitrum = true;
            }
        }
        assertEq(opCount, 4, "not all four OP-stack messages dispatched");
        assertTrue(sawPolygon, "Polygon message not dispatched");
        assertTrue(sawGnosis, "Gnosis message not dispatched");
        assertTrue(sawArbitrum, "Arbitrum retryable not created");
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

    /// @dev Pins the description and the id derived from it, so a drifted description cannot be
    ///      submitted by accident against a reviewed id.
    function test_proposalIdMatchesCommittedDescription() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 dh = keccak256(bytes(description));
        assertEq(dh, 0x993cbb52a409a856560c105510540d773c41589ee5a5b2e46247e5c66801f9ee, "descriptionHash drifted");
        assertEq(
            keccak256(abi.encode(targets, values, calldatas, dh)),
            0x66300d6030c8f24577e001829ada13f1fc221833e53aba4362c492f51049d508,
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
