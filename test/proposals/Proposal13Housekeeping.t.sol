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
