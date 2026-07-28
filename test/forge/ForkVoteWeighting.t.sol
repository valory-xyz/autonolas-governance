// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {VoteWeighting} from "../../contracts/VoteWeighting.sol";

interface IVE {
    function token() external view returns (address);
    function createLock(uint256 amount, uint256 unlockTime) external;
    function lockedEnd(address account) external view returns (uint256);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title ForkVoteWeighting - Mainnet-fork tests for the fixed VoteWeighting against live veOLAS
/// @dev Deploys the patched VoteWeighting bound to the live mainnet veOLAS and replays the
///      remove-without-unvote sequence against real veOLAS slope math, proving the finding #8
///      checkpoint DoS is closed on a realistic build.
///      Run: forge test --fork-url <MAINNET_RPC> --match-contract ForkVoteWeighting -vvv
contract ForkVoteWeighting is Test {
    // Live mainnet veOLAS (the address VoteWeighting binds to as `ve`)
    address constant VEOLAS = 0x7e01A500805f8A52Fad229b3015AD130A332B7b3;

    uint256 constant WEEK = 604_800;
    uint256 constant MAX_WEIGHT = 10_000;
    uint256 constant CHAIN_ID = 100;

    IVE internal ve;
    IERC20 internal olas;
    VoteWeighting internal vw;

    address internal u1 = makeAddr("forkVoter1");
    address internal u2 = makeAddr("forkVoter2");
    address internal u3 = makeAddr("forkVoter3");
    address internal n1 = makeAddr("forkNominee1");
    address internal n2 = makeAddr("forkNominee2");

    function setUp() public {
        // Skip gracefully when not run against a mainnet fork
        if (VEOLAS.code.length == 0) {
            vm.skip(true);
            return;
        }

        ve = IVE(VEOLAS);
        olas = IERC20(ve.token());
        vw = new VoteWeighting(VEOLAS);
    }

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _lock(address user, uint256 amount, uint256 duration) internal {
        deal(address(olas), user, amount);
        vm.startPrank(user);
        olas.approve(address(ve), amount);
        ve.createLock(amount, duration);
        vm.stopPrank();
    }

    function _vote(address user, address nominee, uint256 weight) internal {
        vm.prank(user);
        vw.voteForNomineeWeights(_b32(nominee), CHAIN_ID, weight);
    }

    /// @dev Remove a nominee that still has active votes; no voter unvotes/revokes; walk the
    ///      checkpoint past the voter lock expiries. Must never revert, and the aggregate must
    ///      collapse cleanly to the single surviving nominee's weight.
    function test_Fork_RemoveWithoutUnvote_NoCheckpointDoS() public {
        _lock(u1, 1_000 ether, 20 * WEEK);
        _lock(u2, 1_000 ether, 20 * WEEK);
        _lock(u3, 1_000 ether, 200 * WEEK);

        vw.addNomineeEVM(n1, CHAIN_ID);
        vw.addNomineeEVM(n2, CHAIN_ID);

        _vote(u1, n1, MAX_WEIGHT);
        _vote(u2, n1, MAX_WEIGHT);
        _vote(u3, n2, MAX_WEIGHT);

        // Remove nominee 1 while its votes are live; nobody unvotes
        vw.removeNominee(_b32(n1), CHAIN_ID);

        // Walk the weekly checkpoint well past the nominee-1 lock expiries
        for (uint256 i = 0; i < 40; ++i) {
            vm.warp(block.timestamp + WEEK);
            vw.checkpoint();
        }

        vw.checkpointNominee(_b32(n2), CHAIN_ID);
        uint256 n2Weight = vw.getNomineeWeight(_b32(n2), CHAIN_ID);
        assertGt(n2Weight, 0, "surviving nominee must retain weight");
        assertEq(vw.getWeightsSum(), n2Weight, "aggregate must equal the single surviving nominee");

        // The historically-underflowing removal must now succeed
        vw.removeNominee(_b32(n2), CHAIN_ID);
        assertEq(vw.getWeightsSum(), 0, "aggregate must be zero after removing the last nominee");
    }

    /// @dev Relative weight of a fully-allocated single nominee is exactly 1e18 on the live build.
    function test_Fork_RelativeWeight_FullAllocationIsOne() public {
        _lock(u1, 5_000 ether, 200 * WEEK);
        vw.addNomineeEVM(n1, CHAIN_ID);
        _vote(u1, n1, MAX_WEIGHT);

        vm.warp(block.timestamp + WEEK);
        vw.nomineeRelativeWeightWrite(_b32(n1), CHAIN_ID, block.timestamp);

        (uint256 rw, ) = vw.nomineeRelativeWeight(_b32(n1), CHAIN_ID, block.timestamp);
        assertEq(rw, 1e18, "single fully-allocated nominee must be exactly 1e18");
    }
}
