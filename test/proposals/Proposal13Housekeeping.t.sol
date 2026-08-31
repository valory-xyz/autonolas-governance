// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Proposal13Builder} from "../../scripts/proposals/proposal_13/Proposal13Housekeeping.s.sol";

// Minimal OZ-Governor surface (GovernorOLAS).
interface IGovernor {
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external returns (uint256);
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function proposalEta(uint256 proposalId) external view returns (uint256);
}

interface ITimelock { function hasRole(bytes32 role, address account) external view returns (bool); }

interface IGuardCM {
    function owner() external view returns (address);
    function mapBridgeMediatorL1BridgeParams(address bridgeMediatorL1)
        external view returns (address verifierL2, address bridgeMediatorL2, uint256 chainId);
    function mapAllowedTargetSelectorChainIds(uint256 targetSelectorChainId) external view returns (bool);
    function multisig() external view returns (address);
    function checkTransaction(
        address to, uint256 value, bytes memory data, uint8 operation,
        uint256 safeTxGas, uint256 baseGas, uint256 gasPrice,
        address gasToken, address payable refundReceiver, bytes memory signatures, address msgSender
    ) external;
}

/// @notice L1 validation for proposal 13 on a MAINNET fork, through the CURRENTLY-LIVE GovernorOLAS.
///
///         Entry [0] has a directly observable L1 effect: the Mode route appears in GuardCM.
///         Entries [1] and [2] are bridged, so their L1-observable effect is that the bridge
///         entrypoint accepts the call and emits the outbound message. What the destination chain
///         then does is validated separately by Tenderly simulation on Mode and Polygon — see
///         scripts/proposals/proposal_13/README.md.
///
///         Run: forge test --match-contract Proposal13HousekeepingTest -vvv
contract Proposal13HousekeepingTest is Test, Proposal13Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant FX_STATE_SENDER = 0x28e4F3a7f651294B9564800b2D01f35189A5bFbE;
    address internal constant FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    // Routes configured by proposal 11 that MUST survive this proposal untouched.
    address internal constant OP_L1CDM = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    uint256 internal constant CID_OPTIMISM = 10;

    // The Mode target already carried by the guard's allowlist. The Community Multisig itself is read
    // from the guard at runtime rather than hardcoded — a stale constant here would make the capability
    // test assert against the wrong caller and pass for the wrong reason.
    //
    // ⚠ COLLISION: these 20 bytes are ALSO the L1 `TIMELOCK` in the builder. Same value, opposite meaning
    // — the Timelock on Ethereum, ServiceRegistryL2 on Mode — and `_modeCmScheduleCall()` uses BOTH
    // meanings in one call: `TIMELOCK` as the guard's `to`, this constant inside the bridged payload.
    // Verified on-chain: Ethereum answers `getMinDelay()` and has no `owner()`; Mode answers
    // `owner()` = `drainer()` = the mediator. Do not "simplify" the two into one constant.
    address internal constant MODE_SERVICE_REGISTRY_L2 = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    bytes4 internal constant DRAIN_SEL = bytes4(keccak256(bytes("drain()")));

    // SentMessage(address indexed target, address sender, bytes message, uint256 messageNonce, uint256 gasLimit)
    bytes32 internal constant SENT_MESSAGE_TOPIC =
        keccak256("SentMessage(address,address,bytes,uint256,uint256)");
    // StateSynced(uint256 indexed id, address indexed contractAddress, bytes data)
    bytes32 internal constant STATE_SYNCED_TOPIC = keccak256("StateSynced(uint256,address,bytes)");

    function _fork() internal {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
    }

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    /// @dev Entry [0]'s effect, plus the invariant that the existing routes are untouched.
    function _assertModeRouteSet() internal view {
        (address verifier, address mediatorL2, uint256 chainId) =
            IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(MODE_L1CDM);
        assertEq(verifier, VERIFIER_OPTIMISM, "Mode verifier not set");
        assertEq(mediatorL2, MODE_MESSENGER_L2, "Mode L2 mediator not set");
        assertEq(chainId, CID_MODE, "Mode chainId not set");

        // The Optimism route must be exactly as proposal 11 left it.
        (address opVerifier,, uint256 opChainId) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(OP_L1CDM);
        assertEq(opVerifier, VERIFIER_OPTIMISM, "Optimism verifier disturbed");
        assertEq(opChainId, CID_OPTIMISM, "Optimism chainId disturbed");
    }

    function test_preconditions() public {
        _fork();
        assertTrue(ITimelock(TIMELOCK).hasRole(PROPOSER_ROLE, NEW_GOV), "NEW_GOV not the live proposer");
        assertEq(IGuardCM(GUARD_CM).owner(), TIMELOCK, "GuardCM owner is not the Timelock");

        // The Mode route is currently UNSET — this is the gap the proposal closes.
        (address verifier, address mediatorL2, uint256 chainId) =
            IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(MODE_L1CDM);
        assertEq(verifier, address(0), "Mode verifier already set");
        assertEq(mediatorL2, address(0), "Mode L2 mediator already set");
        assertEq(chainId, 0, "Mode chainId already set");

        // Positive control: the Optimism route IS populated, so a zero above is a real zero and
        // not a getter that silently returns nothing.
        (address opVerifier,, uint256 opChainId) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(OP_L1CDM);
        assertEq(opVerifier, VERIFIER_OPTIMISM, "control: Optimism verifier unset");
        assertEq(opChainId, CID_OPTIMISM, "control: Optimism chainId unset");

        // Both bridge entrypoints must be live contracts.
        assertGt(MODE_L1CDM.code.length, 0, "Mode L1CDM has no code");
        assertGt(FX_ROOT.code.length, 0, "FxRoot has no code");
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
        gov.execute(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertModeRouteSet();
        _assertBridgeMessagesEmitted(vm.getRecordedLogs());

        console2.log("L1 effects asserted: Mode route set; both bridge messages dispatched");
        console2.log("Governor.execute() gas used:", executeGas);
        console2.log("EIP-7825 per-tx cap:        ", uint256(16777216));
        assertLt(executeGas, 16777216, "execute exceeds EIP-7825 per-tx gas cap");
    }

    /// @dev Assert entries [1] and [2] actually handed their payloads to the bridges.
    function _assertBridgeMessagesEmitted(Vm.Log[] memory logs) internal pure {
        bool sawModeMessage;
        bool sawPolygonMessage;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == MODE_L1CDM && logs[i].topics[0] == SENT_MESSAGE_TOPIC) {
                // target is the indexed first argument
                assertEq(address(uint160(uint256(logs[i].topics[1]))), MODE_MESSENGER_L2, "Mode message wrong target");
                sawModeMessage = true;
            }
            if (logs[i].emitter == FX_STATE_SENDER && logs[i].topics[0] == STATE_SYNCED_TOPIC) {
                // StateSynced's indexed `contractAddress` is the FxChild on Polygon, NOT the
                // receiver. FxRoot.sendMessageToChild syncs abi.encode(msg.sender, receiver,
                // payload) to FxChild, so the tunnel address has to be read out of the payload.
                assertEq(address(uint160(uint256(logs[i].topics[2]))), FX_CHILD, "StateSynced not addressed to FxChild");
                bytes memory synced = abi.decode(logs[i].data, (bytes));
                (address rootSender, address receiver,) = abi.decode(synced, (address, address, bytes));
                assertEq(rootSender, TIMELOCK, "Polygon message not sent by the Timelock");
                assertEq(receiver, FX_TUNNEL_L2, "Polygon message wrong receiver");
                sawPolygonMessage = true;
            }
        }
        assertTrue(sawModeMessage, "no SentMessage to the Mode mediator");
        assertTrue(sawPolygonMessage, "no StateSynced to the Polygon tunnel");
    }

    /// @dev Fast path: execute directly as the Timelock (no governor), same assertions.
    function test_L1_fullProposal_executesAsTimelock() public {
        _fork();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();

        vm.recordLogs();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) {
                console2.log("reverted at index", i);
                console2.log("target", targets[i]);
                if (ret.length > 0) {
                    assembly { revert(add(ret, 0x20), mload(ret)) }
                }
                revert("call failed");
            }
        }
        vm.stopPrank();

        _assertModeRouteSet();
        _assertBridgeMessagesEmitted(vm.getRecordedLogs());
    }

    /// @dev Entry [0] exists to restore a capability, not to write three storage words. This asserts the
    ///      capability itself: a Mode-bound Community Multisig schedule is REJECTED by the live guard today
    ///      and ACCEPTED after the proposal executes. It is the assertion that would catch a regression in
    ///      either half — the bridge route or the target/selector allowlist.
    function test_L1_modeCmTransaction_rejectedBefore_acceptedAfter() public {
        _fork();
        address cm = IGuardCM(GUARD_CM).multisig();
        bytes memory scheduleCall = _modeCmScheduleCall();

        // The allowlist half is already in place on the live guard — assert it, so a failure below is
        // attributable to the bridge route and not to a missing target/selector pair.
        assertTrue(
            IGuardCM(GUARD_CM).mapAllowedTargetSelectorChainIds(
                _allowlistKey(MODE_SERVICE_REGISTRY_L2, DRAIN_SEL, CID_MODE)
            ),
            "Mode ServiceRegistryL2.drain() not allowlisted"
        );

        // BEFORE: no Mode route, so the guard falls through to the L1 path and fails closed.
        //
        // Pinned, not a bare expectRevert. The whole weight of "rejected before, accepted after" rests on
        // this leg failing for the STATED reason — a bare one would pass just as happily if the schedule
        // call were malformed or `cm` resolved to something unexpected, and the test would still go green
        // while proving nothing.
        //
        // The revert data is also the evidence for the direct-L1 delta described in the README: chainId 1
        // and selector `sendMessage` mean the guard treated this as an L1 call, because no Mode route
        // existed to route it through the OP-stack verifier.
        vm.prank(cm);
        vm.expectRevert(
            abi.encodeWithSignature(
                "NotAuthorized(address,bytes4,uint256)", MODE_L1CDM, bytes4(0x3dbb202b), uint256(1)
            )
        );
        _checkCmTransaction(scheduleCall, cm);

        _executeProposalAsTimelock();

        // AFTER: the same transaction passes.
        vm.prank(cm);
        _checkCmTransaction(scheduleCall, cm);
        console2.log("Mode CM transaction: rejected before, accepted after");
    }

    /// @dev A Community Multisig transaction scheduling `ServiceRegistryL2.drain()` on Mode, bridged via
    ///      the Mode L1 cross-domain messenger — the shape entry [0] exists to make verifiable.
    function _modeCmScheduleCall() internal pure returns (bytes memory) {
        bytes memory inner = abi.encodeWithSignature("drain()");
        bytes memory l2call = abi.encodeWithSignature(
            "processMessageFromSource(bytes)",
            abi.encodePacked(MODE_SERVICE_REGISTRY_L2, uint96(0), uint32(inner.length), inner)
        );
        return abi.encodeWithSignature(
            "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
            MODE_L1CDM,
            uint256(0),
            abi.encodeWithSignature("sendMessage(address,bytes,uint32)", MODE_MESSENGER_L2, l2call, MODE_MIN_GAS),
            bytes32(0),
            bytes32(0),
            uint256(0)
        );
    }

    function _checkCmTransaction(bytes memory scheduleCall, address cm) internal {
        IGuardCM(GUARD_CM).checkTransaction(
            TIMELOCK, 0, scheduleCall, 0, 0, 0, 0, address(0), payable(address(0)), "", cm
        );
    }

    function _executeProposalAsTimelock() internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok,) = targets[i].call{value: values[i]}(calldatas[i]);
            require(ok, "proposal call failed");
        }
        vm.stopPrank();
    }

    /// @dev GuardCM packs (target | selector | chainId) into one key — target in the low 160 bits,
    ///      selector in the next 32, chain id in the next 64.
    function _allowlistKey(address target, bytes4 selector, uint256 chainId) internal pure returns (uint256 key) {
        key = uint256(uint160(target));
        key |= uint256(uint32(selector)) << 160;
        key |= chainId << 192;
    }

    /// @dev The committed artifacts must match the builder, not merely each other. The builder header warns
    ///      that description.txt has to match byte-for-byte; this checks the file rather than trusting it.
    function test_committedArtifactsMatchTheBuilder() public view {
        (address[] memory targets,, bytes[] memory calldatas, string memory description) = buildProposal();

        string memory onDisk = vm.readFile("scripts/proposals/proposal_13/description.txt");
        assertEq(keccak256(bytes(onDisk)), keccak256(bytes(description)), "description.txt has drifted from the builder");

        string memory json = vm.readFile("scripts/proposals/proposal_13/calldata.json");
        for (uint256 i; i < targets.length; ++i) {
            string memory ix = vm.toString(i);
            assertEq(
                vm.parseJsonBytes(json, string.concat("$[", ix, "].calldata")), calldatas[i],
                string.concat("calldata.json entry ", ix, " has drifted from the builder")
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat("$[", ix, "].target")), targets[i],
                string.concat("calldata.json target ", ix, " has drifted from the builder")
            );
        }
    }

    /// @dev The proposal must not be submittable by accident with a drifted description.
    function test_proposalIdMatchesCommittedDescription() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 dh = keccak256(bytes(description));
        assertEq(dh, 0xfc97ad5c460cb572b31ee9f3c4bfb17e114055fdabfad7e56e0c8c07d30cdeb9, "descriptionHash drifted");
        uint256 id = uint256(keccak256(abi.encode(targets, values, calldatas, dh)));
        assertEq(id, 100619077063411664334557367612251066850008502834926962826958681194909586886778, "proposalId drifted");
    }
}
