// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Test.sol";
import {GovernorOLAS, IVotes, TimelockController} from "../../../../contracts/GovernorOLAS.sol";
import {Timelock} from "../../../../contracts/Timelock.sol";

// Controlled vote weights isolate governance state transitions; no claim about live token history.
contract ReviewVotes {
    mapping(address => uint256) public power;
    function set(address a, uint256 p) external { power[a] = p; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return power[a]; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000e18; }
}

contract GovernanceReviewTest is Test {
    GovernorOLAS gov;
    Timelock tl;
    ReviewVotes token;
    address whale = address(0x111);
    address small = address(0x222);
    address stranger = address(0x333);
    uint256 serial;

    function setUp() public {
        vm.roll(100); vm.warp(1_000_000);
        token = new ReviewVotes(); token.set(whale, 200e18); token.set(small, 20e18);
        tl = new Timelock(0, new address[](0), new address[](0));
        gov = new GovernorOLAS(IVotes(address(token)), TimelockController(payable(address(tl))), 1, 5, 10e18, 3, 10);
        tl.grantRole(tl.PROPOSER_ROLE(), address(gov));
        tl.grantRole(tl.EXECUTOR_ROLE(), address(gov));
        tl.grantRole(tl.CANCELLER_ROLE(), address(gov));
        tl.renounceRole(tl.TIMELOCK_ADMIN_ROLE(), address(this));
    }

    function noop() external {}

    function arrays(address target, bytes memory data) internal pure returns(address[] memory t,uint256[] memory v,bytes[] memory c) {
        t=new address[](1);t[0]=target;v=new uint256[](1);c=new bytes[](1);c[0]=data;
    }
    function pass(address target,bytes memory data) internal returns(uint256 id) {
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(target,data);
        string memory description=vm.toString(++serial);
        vm.prank(whale);id=gov.propose(t,v,c,description);
        vm.roll(gov.proposalSnapshot(id)+1);vm.prank(whale);gov.castVote(id,1);
        vm.roll(gov.proposalDeadline(id)+1);gov.queue(t,v,c,keccak256(bytes(description)));
        vm.warp(gov.proposalEta(id)+1);vm.roll(block.number+1);
        gov.execute(t,v,c,keccak256(bytes(description)));
    }

    function test_ThresholdIncreaseMakesExistingQueuedProposalCancellable() public {
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(this),abi.encodeCall(this.noop,()));
        vm.prank(small);uint256 id=gov.propose(t,v,c,"small-holder proposal");
        vm.roll(gov.proposalSnapshot(id)+1);vm.prank(whale);gov.castVote(id,1);
        vm.roll(gov.proposalDeadline(id)+1);gov.queue(t,v,c,keccak256("small-holder proposal"));
        vm.prank(stranger);vm.expectRevert("GovernorBravo: proposer above threshold");gov.cancel(id);
        pass(address(gov),abi.encodeWithSignature("setProposalThreshold(uint256)",100e18));
        vm.prank(stranger);gov.cancel(id);
        assertEq(uint256(gov.state(id)),2);
    }

    function test_QuorumHistoryPreservedButNewNumeratorStartsAtExecutionBlock() public {
        uint256 beforeBlock=block.number;
        pass(address(gov),abi.encodeWithSignature("updateQuorumNumerator(uint256)",10));
        uint256 executionBlock=block.number;
        assertEq(gov.quorumNumerator(beforeBlock),3);
        assertEq(gov.quorumNumerator(executionBlock-1),3);
        assertEq(gov.quorumNumerator(executionBlock),10);
        assertEq(gov.quorum(executionBlock-1),30e18);
        vm.roll(executionBlock+1);assertEq(gov.quorum(executionBlock),100e18);
    }

    function test_RaisingTimelockDelayAlonePreventsQueueingTheRepair() public {
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",20));
        assertEq(gov.governorDelay(),10);assertEq(tl.getMinDelay(),20);
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateGovernorDelay(uint256)",20));
        vm.prank(whale);uint256 id=gov.propose(t,v,c,"repair delay");
        vm.roll(gov.proposalSnapshot(id)+1);vm.prank(whale);gov.castVote(id,1);
        vm.roll(gov.proposalDeadline(id)+1);
        vm.expectRevert("TimelockController: insufficient delay");gov.queue(t,v,c,keccak256("repair delay"));
        // Timelock identity alone does not bypass the Governor's authorized-call queue.
        vm.prank(address(tl));vm.expectRevert();gov.updateGovernorDelay(20);
    }

    function test_ZeroTimelockReplacementExecutesThenPreventsFurtherQueueing() public {
        pass(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(0)));
        assertEq(gov.timelock(),address(0));
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(tl)));
        vm.prank(whale);uint256 id=gov.propose(t,v,c,"repair timelock");
        vm.roll(gov.proposalSnapshot(id)+1);vm.prank(whale);gov.castVote(id,1);
        vm.roll(gov.proposalDeadline(id)+1);
        vm.expectRevert();gov.queue(t,v,c,keccak256("repair timelock"));
    }

    function test_TimelockIdentityAloneCannotChangeGovernorSettings() public {
        vm.prank(address(tl));vm.expectRevert();gov.setProposalThreshold(1);
        assertEq(gov.proposalThreshold(),10e18);
    }
}
