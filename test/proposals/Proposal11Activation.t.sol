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

/// @title Proposal11Activation fork test
/// @dev Executes the activation proposal as the Timelock (the executor for every call) against a
///      mainnet fork, and asserts the resulting on-chain state. This validates the calldata is correct
///      and will not revert. It does NOT run the full propose->vote->queue lifecycle (that adds nothing
///      to calldata correctness); execution-by-Timelock is exactly what the queued batch does.
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

    /// @dev Whole batch executes without reverting and every effect lands.
    function test_FullProposalExecutes() public {
        _execAll();

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
}
