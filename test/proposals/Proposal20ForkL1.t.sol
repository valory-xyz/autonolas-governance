// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal20} from "../../scripts/proposals/proposal_20/Proposal20.s.sol";

interface IManaged {
    function dispenser() external view returns (address);
}
interface IDispenser {
    function paused() external view returns (uint8);
}
interface ITreasury {
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external returns (bool);
}

/// @dev Forks Ethereum mainnet and executes the three proposal entries directly as the Timelock,
///      asserting no revert and the intended L1 end state: both managers repointed to the new Dispenser
///      proxy, the proxy unpaused, and the old Dispenser no longer authorised to pull from the Treasury.
/// Run: cd <repo> && ETH_RPC_URL=<rpc> forge test --match-contract Proposal20ForkL1 -vv
contract Proposal20ForkL1 is Test {
    address constant TIMELOCK      = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant TOKENOMICS    = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address constant TREASURY      = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address constant OLD_DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;
    address constant NEW_PROXY     = 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D;
    // Pinned for reproducibility; override with ETH_FORK_BLOCK. Recorded in TEST_RECORD.md.
    uint256 constant ETH_FORK_BLOCK = 26500400;

    Proposal20 p;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), vm.envOr("ETH_FORK_BLOCK", ETH_FORK_BLOCK));
        p = new Proposal20();
    }

    function test_execute_L1() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c,) = p.buildProposal();

        uint256 total;
        for (uint256 i; i < v.length; ++i) total += v[i];
        assertEq(total, 0, "proposal should require no ETH");

        // pre-state: both managers still point at the old Dispenser; new proxy still paused.
        assertEq(IManaged(TOKENOMICS).dispenser(), OLD_DISPENSER, "tokenomics dispenser not old pre-exec");
        assertEq(IManaged(TREASURY).dispenser(),   OLD_DISPENSER, "treasury dispenser not old pre-exec");
        assertEq(IDispenser(NEW_PROXY).paused(),    2,            "new proxy not StakingIncentivesPaused pre-exec");

        vm.startPrank(TIMELOCK);
        for (uint256 i; i < t.length; ++i) {
            (bool ok,) = t[i].call{value: v[i]}(c[i]);
            assertTrue(ok, "proposal entry reverted");
        }
        vm.stopPrank();

        // post-state: both managers repointed to the new proxy; proxy unpaused.
        assertEq(IManaged(TOKENOMICS).dispenser(), NEW_PROXY, "tokenomics dispenser not repointed");
        assertEq(IManaged(TREASURY).dispenser(),   NEW_PROXY, "treasury dispenser not repointed");
        assertEq(IDispenser(NEW_PROXY).paused(),    0,        "new proxy not unpaused");

        // the old Dispenser can no longer pull from the Treasury (withdrawToAccount gates on dispenser==msg.sender).
        vm.prank(OLD_DISPENSER);
        vm.expectRevert();
        ITreasury(TREASURY).withdrawToAccount(address(0xdead), 0, 0);
    }
}
