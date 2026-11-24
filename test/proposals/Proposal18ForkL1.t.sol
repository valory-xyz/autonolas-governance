// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal18} from "../../scripts/proposals/proposal_18/Proposal18.s.sol";

interface IGuardCM {
    function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view returns (bool);
}
interface IDispenser {
    function paused() external view returns (uint8);
}

/// @dev Forks Ethereum mainnet and executes the three proposal entries directly as the Timelock,
///      asserting no revert and the intended L1 end state. The Celo entry (c) is the L1 send on the
///      cross-domain messenger; its destination effect is covered by Proposal18Celo.
/// Run: cd <repo> && ETH_RPC_URL=<rpc> forge test --match-contract Proposal18ForkL1 -vv
contract Proposal18ForkL1 is Test {
    address constant TIMELOCK      = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant OLD_DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;
    address constant GUARDCM       = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;
    address constant NEW_PROXY     = 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D;
    bytes4  constant PAUSE_SEL     = 0x8456cb59; // pause()
    bytes4  constant SETPAUSE_SEL  = 0x63096509; // setPauseState(uint8)
    // Pinned for reproducibility; override with ETH_FORK_BLOCK. Recorded in TEST_RECORD.md.
    uint256 constant ETH_FORK_BLOCK = 26485290;

    Proposal18 p;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), vm.envOr("ETH_FORK_BLOCK", ETH_FORK_BLOCK));
        p = new Proposal18();
    }

    function test_execute_L1() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c,) = p.buildProposal();

        uint256 total;
        for (uint256 i; i < v.length; ++i) total += v[i];
        assertEq(total, 0, "proposal should require no ETH");

        // pre-state
        assertEq(IDispenser(OLD_DISPENSER).paused(), 0, "old dispenser already paused");
        assertFalse(IGuardCM(GUARDCM).getTargetSelectorChainId(NEW_PROXY, PAUSE_SEL, 1), "new-proxy pause() row already set");
        // the CM currently holds setPauseState on the old Dispenser — this is what entry (b) row 1 revokes
        assertTrue(IGuardCM(GUARDCM).getTargetSelectorChainId(OLD_DISPENSER, SETPAUSE_SEL, 1), "old setPauseState row expected set pre-exec");

        vm.startPrank(TIMELOCK);
        for (uint256 i; i < t.length; ++i) {
            (bool ok,) = t[i].call{value: v[i]}(c[i]);
            assertTrue(ok, "proposal entry reverted");
        }
        vm.stopPrank();

        // post-state
        assertEq(IDispenser(OLD_DISPENSER).paused(), 2, "old dispenser not StakingIncentivesPaused");
        assertTrue(IGuardCM(GUARDCM).getTargetSelectorChainId(NEW_PROXY, PAUSE_SEL, 1), "new-proxy pause() row not granted");
        // the CM can no longer reopen the paused claim path on the old Dispenser
        assertFalse(IGuardCM(GUARDCM).getTargetSelectorChainId(OLD_DISPENSER, SETPAUSE_SEL, 1), "old setPauseState row not revoked");
    }
}
