// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal18} from "../../scripts/proposals/proposal_18/Proposal18.s.sol";

interface IMediator {
    function processMessageFromSource(bytes memory data) external payable;
}
interface IRegistry {
    function mapMultisigs(address multisig) external view returns (bool);
}

/// @dev Forks Celo and simulates the OP-stack delivery of the proposal's Celo leg (entry 2). The delivered
///      payload and the forwarded-gas budget are BOTH derived from the Forge builder's entry 2 — not
///      hardcoded — so the test exercises exactly what is voted. The L2 cross-domain messenger calls the
///      governance mediator with xDomainMessageSender == the L1 Timelock, and the mediator unpacks and runs
///      the batch. Asserts the legacy wrapper permission is revoked AND that delivery fits the forwarded gas
///      budget the proposal sizes (the destination gas-forward check the proposal checklist requires).
///
/// Simulation boundary: the real L1->L2 message passing is not exercised; delivery is modelled by pranking the
/// L2 messenger predeploy and mocking xDomainMessageSender(). See scripts/proposals/proposal_18/TEST_RECORD.md.
/// Run: cd <repo> && CELO_RPC_URL=<rpc> forge test --match-contract Proposal18Celo -vv
contract Proposal18Celo is Test {
    address constant TIMELOCK  = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant OP_L2_XDM = 0x4200000000000000000000000000000000000007; // L2CrossDomainMessenger predeploy
    address constant REGISTRY  = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address constant WRAPPER   = 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b;
    // Pinned for reproducibility; override with CELO_FORK_BLOCK. Recorded in TEST_RECORD.md.
    uint256 constant CELO_FORK_BLOCK = 83626048;

    Proposal18 p;

    function setUp() public {
        vm.createSelectFork(vm.envString("CELO_RPC_URL"), vm.envOr("CELO_FORK_BLOCK", CELO_FORK_BLOCK));
        p = new Proposal18();
    }

    // Strip the 4-byte function selector so the remainder can be abi.decode'd.
    function _args(bytes memory data) internal pure returns (bytes memory out) {
        require(data.length >= 4, "short calldata");
        out = new bytes(data.length - 4);
        for (uint256 i = 0; i < out.length; ++i) out[i] = data[i + 4];
    }

    function test_celo_revoke_fromBuilder() public {
        // Derive mediator, delivered payload and forwarded gas from the proposal's entry 2.
        (, , bytes[] memory c, ) = p.buildProposal();
        (address mediator, bytes memory inner, uint32 gasForwarded) =
            abi.decode(_args(c[2]), (address, bytes, uint32));
        bytes memory payload = abi.decode(_args(inner), (bytes));

        assertTrue(IRegistry(REGISTRY).mapMultisigs(WRAPPER), "wrapper not currently permitted");

        // Deliver as the L2 messenger, with the L1 source == Timelock (the mediator's sourceGovernor).
        vm.mockCall(OP_L2_XDM, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(TIMELOCK));
        vm.prank(OP_L2_XDM);
        uint256 g0 = gasleft();
        IMediator(mediator).processMessageFromSource(payload);
        uint256 used = g0 - gasleft();

        assertFalse(IRegistry(REGISTRY).mapMultisigs(WRAPPER), "wrapper permission not revoked");
        assertLt(used, gasForwarded, "delivery exceeds the forwarded gas budget the proposal sizes");
        console2.log("celo delivery gas used:", used, "of forwarded budget:", gasForwarded);
    }
}
