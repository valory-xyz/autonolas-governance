// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal17Activation} from "../../scripts/proposals/proposal_17/Proposal17Activation.s.sol";

// L1 execution fork test for proposal 17.
// Funds the Timelock from the deployer EOA (as will happen before execution), executes all 28
// top-level actions as the Timelock at the 50 gwei base-fee ceiling, asserts no revert (which
// includes both Arbitrum/Robinhood Inbox calls — i.e. the per-call submission fee is sized
// correctly at the ceiling), and checks the Ethereum (L1) end state.
// Run: cd <repo> && ETH_RPC_URL=<rpc> forge test --match-contract Proposal17ForkL1 -vv
contract Proposal17ForkL1 is Test {
    Proposal17Activation internal p;

    address constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant EOA      = 0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E; // deployer that funds the Timelock

    // Ethereum targets / expected end state
    address constant MKT_PROXY   = 0x3d6494CE09a9f40c0B5a92BdBD7c7A9b0e3912b1;
    address constant MKT_IMPL    = 0x43D9DeBe4a539334462d1e96068918B8B19650d3;
    address constant MKT_NAT_NEW = 0xf5648BB207ce909D76C219c709433d3Ac05E8B86;
    address constant MKT_USDC_NEW= 0x1F7f307Ecd0ea3778dE3Eb961dEc5A0f814AFCcf;
    address constant MKT_NAT_OLD = 0x3515a36AF270070635Fa3E957e006aaF6078e658;
    address constant MKT_USDC_OLD= 0xF95BfBBA428dfb454Cd59C9c2d309bd6452d12A8;
    address constant SM_PROXY    = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9;
    address constant SR          = 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA;
    address constant WRAP_NEW    = 0x48BE9146eBe74Af8f9BbC42A0EB68B484AC8Df31;
    address constant WRAP_OLD    = 0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461;
    address constant VERIFIER    = 0x4503b79d468e81Ad2d4bd6Db991810da269bA777;
    address constant ST_NEW      = 0x3A8867A5A31c5E26e6b8c740c1E1Aa920802d4BA;
    address constant ST_OLD      = 0x0Dc23eEf3bC64CF3cbd8f9329B57AE4C4f28d5d2;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        p = new Proposal17Activation();
    }

    function _addr(address t, string memory sig, bytes memory args) internal view returns (address) {
        (bool ok, bytes memory r) = t.staticcall(bytes.concat(bytes4(keccak256(bytes(sig))), args));
        require(ok, "staticcall failed");
        return abi.decode(r, (address));
    }
    function _bool(address t, string memory sig, bytes memory args) internal view returns (bool) {
        (bool ok, bytes memory r) = t.staticcall(bytes.concat(bytes4(keccak256(bytes(sig))), args));
        require(ok, "staticcall failed");
        return abi.decode(r, (bool));
    }
    function _uint(address t, string memory sig) internal view returns (uint256) {
        (bool ok, bytes memory r) = t.staticcall(abi.encodeWithSignature(sig));
        require(ok, "staticcall failed");
        return abi.decode(r, (uint256));
    }
    function _ver(address t) internal view returns (string memory) {
        (bool ok, bytes memory r) = t.staticcall(abi.encodeWithSignature("VERSION()"));
        require(ok, "VERSION failed");
        return abi.decode(r, (string));
    }

    function test_execute_L1_and_inbox_fee() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = p.buildProposal();
        uint256 total;
        for (uint256 i; i < values.length; ++i) total += values[i];

        // 1) Deployer EOA funds the Timelock with the exact retryable total (as before execution).
        vm.deal(EOA, total + 1 ether);
        uint256 tlBefore = TIMELOCK.balance;
        vm.prank(EOA);
        (bool funded,) = TIMELOCK.call{value: total}("");
        assertTrue(funded, "EOA could not fund Timelock");
        assertEq(TIMELOCK.balance, tlBefore + total, "Timelock not funded with exact total");

        // 2) Worst-case L1 base fee at the configured ceiling (the Inbox submission-fee check).
        vm.fee(50 gwei);

        // 3) Execute every action as the Timelock (what Timelock.executeBatch does). No entry may revert
        //    — this includes the 15 retryable Inbox calls, proving the per-call maxSubmissionCost holds
        //    at 50 gwei.
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) {
                console2.log("REVERT at entry", i, "target", targets[i]);
                console2.logBytes(ret);
            }
            assertTrue(ok, "proposal entry reverted");
        }
        vm.stopPrank();

        // 4) Ethereum end state.
        assertEq(_addr(MKT_PROXY, "getImplementation()", ""), MKT_IMPL, "marketplace impl not upgraded");
        assertTrue(_bool(MKT_PROXY, "mapMechFactories(address)", abi.encode(MKT_NAT_NEW)), "new native factory not enabled");
        assertTrue(_bool(MKT_PROXY, "mapMechFactories(address)", abi.encode(MKT_USDC_NEW)), "new USDC factory not enabled");
        assertFalse(_bool(MKT_PROXY, "mapMechFactories(address)", abi.encode(MKT_NAT_OLD)), "old native factory still enabled");
        assertFalse(_bool(MKT_PROXY, "mapMechFactories(address)", abi.encode(MKT_USDC_OLD)), "old USDC factory still enabled");

        assertEq(_ver(SM_PROXY), "1.3.0", "ServiceManager not 1.3.0");

        assertTrue(_bool(SR, "mapMultisigs(address)", abi.encode(WRAP_NEW)), "new wrapper not enabled");
        assertFalse(_bool(SR, "mapMultisigs(address)", abi.encode(WRAP_OLD)), "old wrapper still enabled");

        assertEq(_uint(VERIFIER, "numServicesLimit()"), 44, "numServicesLimit not 44");
        assertTrue(_bool(VERIFIER, "mapImplementations(address)", abi.encode(ST_NEW)), "0.4.0 not allowlisted");
        assertFalse(_bool(VERIFIER, "mapImplementations(address)", abi.encode(ST_OLD)), "old StakingToken still allowlisted");

        console2.log("L1 effects OK; 28 actions executed; total funded (wei):", total);
    }
}
