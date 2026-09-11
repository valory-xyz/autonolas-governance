// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal16Builder} from "../../scripts/proposals/proposal_16/Proposal16Robinhood.s.sol";

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

interface IGuardCM {
    function owner() external view returns (address);
    function mapBridgeMediatorL1BridgeParams(address bridgeMediatorL1)
        external view returns (address verifierL2, address bridgeMediatorL2, uint256 chainId);
    function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool);
    function multisig() external view returns (address);
    function checkTransaction(
        address to, uint256 value, bytes memory data, uint8 operation,
        uint256 safeTxGas, uint256 baseGas, uint256 gasPrice,
        address gasToken, address payable refundReceiver, bytes memory signatures, address msgSender
    ) external;
}

interface IDispenser {
    function owner() external view returns (address);
    function mapChainIdDepositProcessors(uint256 chainId) external view returns (address);
}

interface IProcessor { function l2TargetChainId() external view returns (uint256); }

/// @notice L1 validation for proposal 16 on a MAINNET fork, through the CURRENTLY-LIVE GovernorOLAS.
///
///         Unlike proposal 13, all three entries are direct L1 calls — nothing is bridged — so every
///         effect of this proposal is observable on the fork. There is no destination-chain leg to
///         validate by Tenderly.
///
///         Run: forge test --match-contract Proposal16RobinhoodTest -vvv
contract Proposal16RobinhoodTest is Test, Proposal16Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    bytes4 internal constant SELECTOR_UNPAUSE = 0x3f4ba83a; // not granted — asserted absent
    bytes4 internal constant CREATE_RETRYABLE_TICKET =
        bytes4(keccak256(bytes("createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)")));
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    // The Arbitrum One route, configured by proposal 11, MUST survive untouched. It shares this
    // proposal's verifier AND its L2 mediator address, so a mistake that overwrote Arbitrum's entry
    // would still leave two of the three fields looking right — only the chain Id would betray it.
    address internal constant ARBITRUM_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    uint256 internal constant CID_ARBITRUM = 42161;
    address internal constant ARBITRUM_SERVICE_MANAGER_PROXY = 0xD421f433e36465B3e558B1121F584ac09Fc33DF8;

    function _fork() internal {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
    }

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    /// @dev Everything this proposal sets must be unset first, or the test proves nothing.
    function test_preconditions() public {
        _fork();

        assertEq(IDispenser(DISPENSER).owner(), TIMELOCK, "Dispenser owner is not the Timelock");
        assertEq(IGuardCM(GUARD_CM).owner(), TIMELOCK, "GuardCM owner is not the Timelock");

        assertEq(IDispenser(DISPENSER).mapChainIdDepositProcessors(CID_ROBINHOOD), address(0), "4663 processor already set");

        (address v, address m, uint256 c) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(ROBINHOOD_INBOX);
        assertEq(v, address(0), "4663 verifier already set");
        assertEq(m, address(0), "4663 mediator already set");
        assertEq(c, 0, "4663 chainId already set");

        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_MANAGER_PROXY, SELECTOR_PAUSE, CID_ROBINHOOD), "triple already set");
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_TARGET_DISPENSER_L2, SELECTOR_PAUSE, CID_ROBINHOOD), "triple already set");
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_REGISTRY_L2, SELECTOR_DRAIN, CID_ROBINHOOD), "triple already set");
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_REGISTRY_TOKEN_UTILITY, SELECTOR_DRAIN_TOKEN, CID_ROBINHOOD), "triple already set");

        // The fleet parity this proposal's entry 2 is built on. unpause() is allowlisted on NO
        // chain, so if any of these ever reads true the selector set here needs rethinking, not
        // copying.
        assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(ARBITRUM_SERVICE_MANAGER_PROXY, SELECTOR_PAUSE, CID_ARBITRUM), "parity: Arbitrum pause missing");
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ARBITRUM_SERVICE_MANAGER_PROXY, SELECTOR_UNPAUSE, CID_ARBITRUM), "parity: Arbitrum unpause is granted");

        // Positive control: the Arbitrum route IS populated, so the zeros above are real zeros and
        // not a getter that silently returns nothing.
        (address av, address am, uint256 ac) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(ARBITRUM_INBOX);
        assertEq(av, VERIFIER_ARBITRUM, "control: Arbitrum verifier unset");
        assertEq(am, ROBINHOOD_MEDIATOR_L2, "control: Arbitrum mediator is not the shared alias");
        assertEq(ac, CID_ARBITRUM, "control: Arbitrum chainId unset");

        // The L1 entrypoint and the processor must be live, and the processor must be 4663's.
        assertGt(ROBINHOOD_INBOX.code.length, 0, "Robinhood inbox has no code");
        assertGt(VERIFIER_ARBITRUM.code.length, 0, "Orbit verifier has no code");
        assertEq(IProcessor(ROBINHOOD_PROCESSOR_L1).l2TargetChainId(), CID_ROBINHOOD, "processor is not 4663's");
    }

    function test_L1_fullGovernanceLifecycle() public {
        _fork();
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 dh = keccak256(bytes(description));
        IGovernor gov = IGovernor(NEW_GOV);

        // The id the artifacts publish must be the id the governor assigns.
        uint256 expectedId = uint256(keccak256(abi.encode(targets, values, calldatas, dh)));

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");

        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        assertEq(id, expectedId, "proposalId differs from the builder's computation");

        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);

        uint256 g = gasleft();
        gov.execute(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertAllThreeEffects();
        _assertArbitrumUntouched();

        console2.log("L1 effects asserted: processor registered, 4663 route set, 4 triples allowlisted");
        console2.log("Governor.execute() gas used:", executeGas);
    }

    function _assertAllThreeEffects() internal view {
        // [0] the Dispenser now routes 4663 to its processor.
        assertEq(
            IDispenser(DISPENSER).mapChainIdDepositProcessors(CID_ROBINHOOD),
            ROBINHOOD_PROCESSOR_L1,
            "entry 0: 4663 processor not registered"
        );

        // [1] GuardCM holds the 4663 route. verifierL2 != 0 is the exact check Mode failed.
        (address v, address m, uint256 c) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(ROBINHOOD_INBOX);
        assertEq(v, VERIFIER_ARBITRUM, "entry 1: wrong verifier");
        assertEq(m, ROBINHOOD_MEDIATOR_L2, "entry 1: wrong mediator");
        assertEq(c, CID_ROBINHOOD, "entry 1: wrong chainId");

        // [2] the four triples are allowlisted for 4663 — and unpause() is NOT.
        assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_MANAGER_PROXY, SELECTOR_PAUSE, CID_ROBINHOOD), "entry 2: SMP.pause");
        assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_TARGET_DISPENSER_L2, SELECTOR_PAUSE, CID_ROBINHOOD), "entry 2: dispenser.pause");
        assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_REGISTRY_L2, SELECTOR_DRAIN, CID_ROBINHOOD), "entry 2: SR.drain()");
        assertTrue(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_REGISTRY_TOKEN_UTILITY, SELECTOR_DRAIN_TOKEN, CID_ROBINHOOD), "entry 2: STU.drain(address)");

        // The negative is the point of the review that produced this shape: granting unpause()
        // would let the CM lift a pause on 4663 in one transaction with no vote, a power it holds
        // on no other chain.
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_SERVICE_MANAGER_PROXY, SELECTOR_UNPAUSE, CID_ROBINHOOD), "entry 2: SMP.unpause must NOT be granted");
        assertFalse(IGuardCM(GUARD_CM).getTargetSelectorChainId(ROBINHOOD_TARGET_DISPENSER_L2, SELECTOR_UNPAUSE, CID_ROBINHOOD), "entry 2: dispenser.unpause must NOT be granted");
    }

    /// @notice What the guard actually admits, not just what it stores. Modelled on proposal 13's
    ///         CM leg: build a real community-multisig `schedule` carrying an Orbit retryable to
    ///         4663, and show it is rejected before the proposal and accepted after.
    ///
    ///         This is the Mode lesson made executable. Mode spent two months with allowlist
    ///         entries and no bridge params, where exactly this call failed closed — storage said
    ///         yes and the guard said no.
    function test_CM_canPause4663_onlyAfterProposal() public {
        _fork();

        address cm = IGuardCM(GUARD_CM).multisig();
        bytes memory scheduleCall = _robinhoodCmScheduleCall(ROBINHOOD_SERVICE_MANAGER_PROXY, abi.encodeWithSignature("pause()"));

        // BEFORE: no 4663 route, so the guard falls through to its L1 path and fails closed.
        // Pinned rather than a bare expectRevert: the weight of "rejected before, accepted after"
        // rests on this leg failing for the stated reason. chainId 1 and the createRetryableTicket
        // selector are the evidence that the guard treated it as an L1 call, because no 4663 route
        // existed to route it through the Orbit verifier.
        vm.prank(cm);
        vm.expectRevert(
            abi.encodeWithSignature(
                "NotAuthorized(address,bytes4,uint256)", ROBINHOOD_INBOX, CREATE_RETRYABLE_TICKET, uint256(1)
            )
        );
        _checkCmTransaction(scheduleCall, cm);

        _executeProposalAsTimelock();

        // AFTER: the same transaction passes, for both pausable targets.
        vm.prank(cm);
        _checkCmTransaction(scheduleCall, cm);
        vm.prank(cm);
        _checkCmTransaction(
            _robinhoodCmScheduleCall(ROBINHOOD_TARGET_DISPENSER_L2, abi.encodeWithSignature("pause()")), cm
        );

        // And unpause() is still refused, because it was never allowlisted.
        vm.prank(cm);
        vm.expectRevert();
        _checkCmTransaction(
            _robinhoodCmScheduleCall(ROBINHOOD_SERVICE_MANAGER_PROXY, abi.encodeWithSignature("unpause()")), cm
        );

        console2.log("4663 CM pause(): rejected before, accepted after; unpause() still refused");
    }

    /// @dev A community-multisig transaction scheduling `targetPayload` on `target` over 4663,
    ///      bridged as an Orbit retryable through the Robinhood Delayed Inbox. The refund
    ///      addresses must both be the L2 mediator or ProcessBridgedDataArbitrum rejects it.
    function _robinhoodCmScheduleCall(address target, bytes memory targetPayload)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory ticket = abi.encodeWithSignature(
            "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
            target,
            uint256(0), // l2CallValue — must be zero
            uint256(0),
            ROBINHOOD_MEDIATOR_L2, // excessFeeRefundAddress
            ROBINHOOD_MEDIATOR_L2, // callValueRefundAddress
            uint256(0),
            uint256(0),
            targetPayload
        );
        return abi.encodeWithSignature(
            "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
            ROBINHOOD_INBOX,
            uint256(0),
            ticket,
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

    /// @dev Apply the proposal's own calldata as the Timelock, without the governor lifecycle.
    function _executeProposalAsTimelock() internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok,) = targets[i].call{value: values[i]}(calldatas[i]);
            require(ok, "proposal call failed");
        }
        vm.stopPrank();
    }

    /// @dev The shared verifier and shared mediator address make an accidental overwrite of the
    ///      Arbitrum One route hard to spot by eye, so assert it explicitly. The chain Id is the
    ///      field that would change.
    function _assertArbitrumUntouched() internal view {
        (address av, address am, uint256 ac) = IGuardCM(GUARD_CM).mapBridgeMediatorL1BridgeParams(ARBITRUM_INBOX);
        assertEq(av, VERIFIER_ARBITRUM, "Arbitrum verifier changed");
        assertEq(am, ROBINHOOD_MEDIATOR_L2, "Arbitrum mediator changed");
        assertEq(ac, CID_ARBITRUM, "Arbitrum chainId changed");
        assertTrue(
            IGuardCM(GUARD_CM).getTargetSelectorChainId(ARBITRUM_SERVICE_MANAGER_PROXY, SELECTOR_PAUSE, CID_ARBITRUM),
            "Arbitrum triple lost"
        );
    }
}
