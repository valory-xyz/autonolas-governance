// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Test.sol";
import {GovernorOLAS} from "../../../../contracts/GovernorOLAS.sol";
import {Timelock} from "../../../../contracts/Timelock.sol";

// All mutations occur on an isolated local fork. No broadcast or live signing.
contract GovernanceLiveReviewTest is Test {
    GovernorOLAS gov=GovernorOLAS(payable(0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6));
    Timelock tl=Timelock(payable(0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE));
    address whale=0x063923C9b00Bd1eFb1EF5a89498538F5A1237a97;
    function setUp() public {
        vm.createSelectFork(vm.envOr("REVIEW_RPC",string("https://eth.drpc.org")),26032428);
        assertEq(block.chainid,1);
        assertEq(gov.governorDelay(),157092);
        assertEq(tl.getMinDelay(),0);
    }
    function arrays(address target,bytes memory data) internal pure returns(address[] memory t,uint256[] memory v,bytes[] memory c){
        t=new address[](1);t[0]=target;v=new uint256[](1);c=new bytes[](1);c[0]=data;
    }
    function mine(uint256 count) internal {vm.roll(block.number+count);vm.warp(block.timestamp+12*count);}
    function succeed(address[] memory t,uint256[] memory v,bytes[] memory c,string memory d) internal {
        vm.prank(whale);uint256 id=gov.propose(t,v,c,d);
        mine(gov.votingDelay()+1);vm.prank(whale);gov.castVote(id,1);
        mine(gov.votingPeriod()+1);assertEq(uint256(gov.state(id)),4);
    }
    function pass(address target,bytes memory data,string memory d) internal {
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(target,data);
        succeed(t,v,c,d);gov.queue(t,v,c,keccak256(bytes(d)));
        mine(gov.governorDelay()/12+2);gov.execute(t,v,c,keccak256(bytes(d)));
    }
    function test_LiveDelayDesyncPreventsGovernanceRepair() public {
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",200000),"review fork only: raise minimum delay");
        assertEq(tl.getMinDelay(),200000);
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateGovernorDelay(uint256)",200000));
        string memory d="review fork only: repair governor delay";
        succeed(t,v,c,d);
        vm.expectRevert("TimelockController: insufficient delay");gov.queue(t,v,c,keccak256(bytes(d)));
    }
    function test_LiveZeroTimelockAcceptedAndRepairCannotQueue() public {
        pass(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(0)),"review fork only: zero timelock");
        assertEq(gov.timelock(),address(0));
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(tl)));
        string memory d="review fork only: restore timelock";
        succeed(t,v,c,d);
        vm.expectRevert();gov.queue(t,v,c,keccak256(bytes(d)));
    }
}
