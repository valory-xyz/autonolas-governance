// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";

interface IMediator {
    function processMessageFromSource(bytes memory data) external payable;
}
interface IRegistry {
    function mapMultisigs(address multisig) external view returns (bool);
}

/// @dev Forks Celo and simulates the OP-stack delivery of the proposal's Celo leg: the L2
///      cross-domain messenger calls the governance mediator with xDomainMessageSender == the L1
///      Timelock, and the mediator unpacks and runs the batch. Asserts the legacy wrapper permission
///      is revoked AND that delivery fits the forwarded gas budget (OP_MIN_GAS = 2,000,000) — the
///      destination gas-forward check the proposal checklist requires.
/// Run: cd <repo> && CELO_RPC_URL=<rpc> forge test --match-contract Proposal18Celo -vv
contract Proposal18Celo is Test {
    address constant TIMELOCK  = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant OP_L2_XDM = 0x4200000000000000000000000000000000000007; // L2CrossDomainMessenger predeploy
    address constant MEDIATOR  = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d;
    address constant REGISTRY  = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address constant WRAPPER   = 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b;

    function test_celo_revoke() public {
        vm.createSelectFork(vm.envString("CELO_RPC_URL"));

        // The exact batch the mediator receives: packed (target, uint96 value, uint32 len, data).
        bytes memory inner = abi.encodeWithSignature("changeMultisigPermission(address,bool)", WRAPPER, false);
        bytes memory payload = abi.encodePacked(REGISTRY, uint96(0), uint32(inner.length), inner);

        assertTrue(IRegistry(REGISTRY).mapMultisigs(WRAPPER), "wrapper not currently permitted");

        // Deliver as the L2 messenger, with the L1 source == Timelock (the mediator's sourceGovernor).
        vm.mockCall(OP_L2_XDM, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(TIMELOCK));
        vm.prank(OP_L2_XDM);
        uint256 g0 = gasleft();
        IMediator(MEDIATOR).processMessageFromSource(payload);
        uint256 used = g0 - gasleft();

        assertFalse(IRegistry(REGISTRY).mapMultisigs(WRAPPER), "wrapper permission not revoked");
        assertLt(used, 2_000_000, "delivery exceeds OP_MIN_GAS forwarded budget");
        console2.log("celo delivery gas used:", used);
    }
}
