// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Proposal11Builder} from "../../scripts/proposals/proposal_11/Proposal11Activation.s.sol";

interface ITimelock {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IGuardCM {
    function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool);
    function mapBridgeMediatorL1BridgeParams(address l1) external view returns (address verifierL2, address bridgeMediatorL2, uint64 chainId);
}

interface ITokenomicsProxy {
    function tokenomicsImplementation() external view returns (address);
}

interface IGovernor {
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external returns (uint256);
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function proposalEta(uint256 proposalId) external view returns (uint256);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function token() external view returns (address);
    function hashProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external pure returns (uint256);
}

/// @title Proposal11Activation fork test
/// @dev Two checks against a mainnet fork, both asserting the same post-activation state:
///      - test_FullGovernanceLifecycle: the REAL pipeline through the OLD GovernorOLAS + Timelock
///        (propose -> vote -> queue -> execute). Confirms the precomputed proposalId, the state machine,
///        timelock scheduling and the atomic batch execution. Only veOLAS vote-weight reads are mocked.
///      - test_FullProposalExecutes: fast path that executes the batch as the Timelock (final step only).
///
///      Run: forge test --fork-url $MAINNET_RPC --match-contract Proposal11Activation -vvv
contract Proposal11ActivationTest is Test, Proposal11Builder {
    // Gnosis Safe guard storage slot = keccak256("guard_manager.guard.address")
    bytes32 constant SAFE_GUARD_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    function setUp() public {
        assertEq(block.chainid, 1, "Must run on a mainnet fork (--fork-url $MAINNET_RPC)");
    }

    function _execAll() internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) {
                console2.log("Reverted at index", i, "target", targets[i]);
                if (ret.length > 0) {
                    assembly { revert(add(ret, 0x20), mload(ret)) }
                }
                revert("call failed");
            }
        }
        vm.stopPrank();
    }

    /// @dev Sanity: the live state is the pre-activation state we expect (old gov has roles, new doesn't).
    function test_PreconditionsHold() public view {
        ITimelock tl = ITimelock(TIMELOCK);
        assertTrue(tl.hasRole(PROPOSER_ROLE, OLD_GOV), "old gov should have PROPOSER pre-vote");
        assertFalse(tl.hasRole(PROPOSER_ROLE, NEW_GOV), "new gov should not have PROPOSER pre-vote");
    }

    /// @dev Fast path: the batch executes (as the Timelock would in the final step) and every effect lands.
    function test_FullProposalExecutes() public {
        _execAll();
        _assertEndState();
    }

    /// @dev Asserts the full post-activation on-chain state. Shared by both the fast-path and the
    ///      full-governance-lifecycle tests.
    function _assertEndState() internal view {
        ITimelock tl = ITimelock(TIMELOCK);
        // A) roles migrated
        assertTrue(tl.hasRole(TIMELOCK_ADMIN_ROLE, NEW_GOV), "new gov ADMIN");
        assertTrue(tl.hasRole(PROPOSER_ROLE, NEW_GOV), "new gov PROPOSER");
        assertTrue(tl.hasRole(EXECUTOR_ROLE, NEW_GOV), "new gov EXECUTOR");
        assertTrue(tl.hasRole(CANCELLER_ROLE, NEW_GOV), "new gov CANCELLER");
        assertFalse(tl.hasRole(TIMELOCK_ADMIN_ROLE, OLD_GOV), "old gov ADMIN revoked");
        assertFalse(tl.hasRole(PROPOSER_ROLE, OLD_GOV), "old gov PROPOSER revoked");
        assertFalse(tl.hasRole(EXECUTOR_ROLE, OLD_GOV), "old gov EXECUTOR revoked");
        assertFalse(tl.hasRole(CANCELLER_ROLE, OLD_GOV), "old gov CANCELLER revoked");

        // B) bridge mediators set (spot-check Gnosis + Celo)
        IGuardCM g = IGuardCM(NEW_GUARD);
        (address vG, address mG, uint64 cG) = g.mapBridgeMediatorL1BridgeParams(AMB_L1);
        assertEq(vG, VERIFIER_GNOSIS, "gnosis verifier"); assertEq(mG, HOME_MEDIATOR_L2, "gnosis L2"); assertEq(cG, uint64(CID_GNOSIS), "gnosis chain");
        (address vC, address mC, uint64 cC) = g.mapBridgeMediatorL1BridgeParams(CELO_L1CDM);
        assertEq(vC, VERIFIER_OPTIMISM, "celo verifier"); assertEq(mC, CELO_MESSENGER_L2, "celo L2"); assertEq(cC, uint64(CID_CELO), "celo chain");

        // C) allowlist (spot-check mainnet + one L2 per direction)
        assertTrue(g.getTargetSelectorChainId(TREASURY, SEL_PAUSE, CID_MAINNET), "treasury pause");
        assertTrue(g.getTargetSelectorChainId(DEPOSITORY, SEL_CLOSE, CID_MAINNET), "depository close");
        assertTrue(g.getTargetSelectorChainId(SRTU_L1, SEL_DRAIN_ADDRESS, CID_MAINNET), "L1 SRTU drain");
        assertTrue(g.getTargetSelectorChainId(SRL2_BASE, SEL_DRAIN, CID_BASE), "base SRL2 drain");
        assertTrue(g.getTargetSelectorChainId(SRTU_CELO, SEL_DRAIN_ADDRESS, CID_CELO), "celo SRTU drain");

        // D) CM guard swapped
        bytes32 slot = vm.load(CM, SAFE_GUARD_SLOT);
        assertEq(address(uint160(uint256(slot))), NEW_GUARD, "CM guard not swapped");

        // F) tokenomics implementation upgraded
        assertEq(ITokenomicsProxy(TOKENOMICS_PROXY).tokenomicsImplementation(), TOKENOMICS_NEW_IMPL, "tokenomics impl");
        // E) the Celo sendMessage call succeeded (enqueued on L1CrossDomainMessenger). L2 delivery is not
        //    observable on a mainnet fork; correctness of the bridged payload is covered by the encoding +
        //    GuardCM ProcessBridgedDataOptimism verification tests.
    }

    /// @dev REAL end-to-end lifecycle through the OLD GovernorOLAS + Timelock:
    ///      propose -> (advance) -> castVote -> (advance) -> queue -> (warp past eta) -> execute.
    ///      Only the veOLAS voting-power reads are mocked (to isolate the proposal mechanics from token
    ///      distribution); the proposal id, state machine, timelock scheduling and batch execution are real.
    function test_FullGovernanceLifecycle() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        bytes32 descHash = keccak256(bytes(description));
        IGovernor gov = IGovernor(OLD_GOV);
        address token = gov.token(); // wveOLAS used for vote weight
        address proposer = address(0xBEEF);
        address voter = address(0xCAFE);

        // Inject voting power: large weight for any account, moderate total supply so quorum (3%) is cleared.
        vm.mockCall(token, abi.encodeWithSignature("getPastVotes(address,uint256)"), abi.encode(uint256(1e27)));
        vm.mockCall(token, abi.encodeWithSignature("getVotes(address,uint256)"), abi.encode(uint256(1e27)));
        vm.mockCall(token, abi.encodeWithSignature("getPastTotalSupply(uint256)"), abi.encode(uint256(1e24)));

        // propose
        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        assertEq(id, gov.hashProposal(targets, values, calldatas, descHash), "proposalId mismatch");
        console2.log("1) proposed   | id == hashProposal:", id);
        console2.log("   state (0=Pending):", gov.state(id));

        // into Active, then vote For
        vm.roll(block.number + gov.votingDelay() + 1);
        assertEq(uint256(gov.state(id)), 1, "not Active");
        console2.log("2) active     | state (1=Active):", gov.state(id));
        vm.prank(voter);
        gov.castVote(id, 1);
        console2.log("3) voted For");

        // end voting -> Succeeded
        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(uint256(gov.state(id)), 4, "not Succeeded");
        console2.log("4) succeeded  | state (4=Succeeded):", gov.state(id));

        // queue -> Queued, warp past the timelock eta, then execute -> Executed
        gov.queue(targets, values, calldatas, descHash);
        assertEq(uint256(gov.state(id)), 5, "not Queued");
        uint256 eta = gov.proposalEta(id);
        console2.log("5) queued     | state (5=Queued):", gov.state(id));
        console2.log("   timelock eta:", eta);
        if (eta >= block.timestamp) vm.warp(eta + 1);
        gov.execute(targets, values, calldatas, descHash);
        assertEq(uint256(gov.state(id)), 7, "not Executed");
        console2.log("6) executed   | state (7=Executed):", gov.state(id));

        _assertEndState();
        console2.log("7) end-state asserted: roles migrated, guard configured+swapped, tokenomics impl upgraded");
    }
}
