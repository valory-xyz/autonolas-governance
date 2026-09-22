// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {GovernanceLiveReviewTest} from "./GovernanceLiveReview.t.sol";
import {GovernorOLAS} from "../../../../contracts/GovernorOLAS.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IRecoverySafe {
    function getOwners() external view returns(address[] memory);
    function getThreshold() external view returns(uint256);
    function nonce() external view returns(uint256);
    function approveHash(bytes32 hash) external;
    function getTransactionHash(address,uint256,bytes memory,uint8,uint256,uint256,uint256,address,address,uint256) external view returns(bytes32);
    function execTransaction(address,uint256,bytes memory,uint8,uint256,uint256,uint256,address,address payable,bytes memory) external payable returns(bool);
}
interface IRecoveryGuard {
    function paused() external view returns(uint256);
    function governorCheckProposalId() external view returns(uint256);
}

contract GovernanceRecoveryReviewTest is GovernanceLiveReviewTest {
    IRecoverySafe safe=IRecoverySafe(0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570);
    IRecoveryGuard guard=IRecoveryGuard(0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B);

    // Exercises real Safe signature checks and GuardCM. Owner approvals are impersonated
    // locally: this assumes threshold cooperation, not possession of any signing key.
    function safeExec(address target,bytes memory data) internal {
        address[] memory owners=safe.getOwners();
        for(uint256 i=0;i<owners.length;i++)for(uint256 j=i+1;j<owners.length;j++)if(owners[j]<owners[i]){
            (owners[i],owners[j])=(owners[j],owners[i]);
        }
        uint256 threshold=safe.getThreshold();
        bytes32 digest=safe.getTransactionHash(target,0,data,0,0,0,0,address(0),address(0),safe.nonce());
        bytes memory signatures;
        for(uint256 i=0;i<threshold;i++){
            vm.prank(owners[i]);safe.approveHash(digest);
            signatures=abi.encodePacked(signatures,bytes32(uint256(uint160(owners[i]))),bytes32(0),uint8(1));
        }
        assertTrue(safe.execTransaction(target,0,data,0,0,0,0,address(0),payable(address(0)),signatures));
    }
    function safeSchedule(address target,bytes memory data,bytes32 salt,uint256 delay) internal {
        safeExec(address(tl),abi.encodeWithSignature("schedule(address,uint256,bytes,bytes32,bytes32,uint256)",target,0,data,bytes32(0),salt,delay));
    }
    function safeExecute(address target,bytes memory data,bytes32 salt) internal {
        safeExec(address(tl),abi.encodeWithSignature("execute(address,uint256,bytes,bytes32,bytes32)",target,0,data,bytes32(0),salt));
    }
    // Hypothetical prerequisite only. Does NOT demonstrate knowledge/creation of the
    // heartbeat preimage or that a defeated heartbeat exists at the pinned block.
    function conditionalRelease() internal {
        assertEq(guard.paused(),1);
        vm.mockCall(address(gov),abi.encodeWithSignature("state(uint256)",guard.governorCheckProposalId()),abi.encode(uint8(3)));
        safeExec(address(guard),abi.encodeWithSignature("pause()"));
        vm.clearMockedCalls();
        assertEq(guard.paused(),2);
    }
    function test_OutsiderCannotTriggerUnsafeSetters() public {
        vm.expectRevert("Governor: onlyGovernance");gov.updateGovernorDelay(200000);
        vm.expectRevert("Governor: onlyGovernance");gov.updateTimelock(TimelockController(payable(address(0))));
        vm.expectRevert("TimelockController: caller must be timelock");tl.updateDelay(200000);
    }
    // External wrappers isolate the Safe call so expectRevert does not intercept setup getters.
    function attemptSchedule(address target,bytes calldata data) external {
        require(msg.sender==address(this));safeSchedule(target,data,bytes32("blocked"),tl.getMinDelay());
    }
    function attemptRelease() external {
        require(msg.sender==address(this));safeExec(address(guard),abi.encodeWithSignature("pause()"));
    }
    function test_CurrentGuardBlocksCMRepairAndUnknownHeartbeatRelease() public {
        bytes4 denied=bytes4(keccak256("NotAuthorized(address,bytes4,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(denied,address(tl),bytes4(keccak256("updateDelay(uint256)")),uint256(1)));
        this.attemptSchedule(address(tl),abi.encodeWithSignature("updateDelay(uint256)",0));
        vm.expectRevert(abi.encodeWithSelector(denied,address(tl),bytes4(keccak256("grantRole(bytes32,address)")),uint256(1)));
        this.attemptSchedule(address(tl),abi.encodeWithSignature("grantRole(bytes32,address)",keccak256("PROPOSER_ROLE"),address(this)));
        uint256 heartbeat=guard.governorCheckProposalId();
        vm.expectRevert("Governor: unknown proposal id");gov.state(heartbeat);
        // Safe wraps the failed target call; the guard permits calling pause itself.
        vm.expectRevert("GS013");this.attemptRelease();
    }
    function test_PrequeuedGovernorRepairSurvivesRaisedMinimumDelay() public {
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateGovernorDelay(uint256)",200000));
        string memory d="review fork only: prepare governor delay repair";
        succeed(t,v,c,d);gov.queue(t,v,c,keccak256(bytes(d)));
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",200000),"review fork only: desync after prepared repair");
        assertEq(gov.governorDelay(),157092);
        gov.execute(t,v,c,keccak256(bytes(d)));
        assertEq(gov.governorDelay(),tl.getMinDelay());
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",0),"review fork only: demonstrate restored queue");
    }
    function test_AtomicCoupledDelayUpdatePreservesGovernance() public {
        address[] memory t=new address[](2);uint256[] memory v=new uint256[](2);bytes[] memory c=new bytes[](2);
        t[0]=address(tl);c[0]=abi.encodeWithSignature("updateDelay(uint256)",200000);
        t[1]=address(gov);c[1]=abi.encodeWithSignature("updateGovernorDelay(uint256)",200000);
        string memory d="review fork only: atomic coupled update";
        succeed(t,v,c,d);gov.queue(t,v,c,keccak256(bytes(d)));mine(157092/12+2);
        gov.execute(t,v,c,keccak256(bytes(d)));assertEq(gov.governorDelay(),tl.getMinDelay());
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",0),"review fork only: queue remains usable");
    }
    function test_ConditionalReleasedCMCanRepairTimelockDelay() public {
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",200000),"review fork only: desync for conditional CM recovery");
        conditionalRelease();
        bytes memory data=abi.encodeWithSignature("updateDelay(uint256)",0);bytes32 salt=bytes32("cm-delay-repair");
        safeSchedule(address(tl),data,salt,tl.getMinDelay());
        vm.warp(block.timestamp+200001);safeExecute(address(tl),data,salt);
        assertEq(tl.getMinDelay(),0);
        pass(address(tl),abi.encodeWithSignature("updateDelay(uint256)",0),"review fork only: recovered governor works");
    }
    function test_PrequeuedGovernorRestoreCannotRepairZeroPointer() public {
        (address[] memory t,uint256[] memory v,bytes[] memory c)=arrays(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(tl)));
        string memory d="review fork only: prequeue timelock pointer repair";
        succeed(t,v,c,d);gov.queue(t,v,c,keccak256(bytes(d)));
        pass(address(gov),abi.encodeWithSignature("updateTimelock(address)",address(0)),"review fork only: break pointer after prequeue");
        vm.expectRevert();gov.execute(t,v,c,keccak256(bytes(d)));
        // Executing directly through the old Timelock does not satisfy the new zero executor.
        vm.prank(address(safe));vm.expectRevert("TimelockController: underlying transaction reverted");
        tl.executeBatch(t,v,c,bytes32(0),keccak256(bytes(d)));
    }
    function test_ConditionalReleasedCMCanReplaceBrokenGovernor() public {
        address old=address(gov);
        pass(old,abi.encodeWithSignature("updateTimelock(address)",address(0)),"review fork only: broken pointer needs replacement");
        conditionalRelease();
        GovernorOLAS replacement=new GovernorOLAS(IVotes(0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40),TimelockController(payable(address(tl))),13091,19636,250000e18,10,157092);
        bytes32[4] memory roles=[tl.TIMELOCK_ADMIN_ROLE(),tl.PROPOSER_ROLE(),tl.EXECUTOR_ROLE(),tl.CANCELLER_ROLE()];
        address[] memory t=new address[](9);uint256[] memory v=new uint256[](9);bytes[] memory c=new bytes[](9);
        for(uint256 i=0;i<4;i++){
            t[i]=address(tl);c[i]=abi.encodeWithSignature("grantRole(bytes32,address)",roles[i],address(replacement));
            t[i+4]=address(tl);c[i+4]=abi.encodeWithSignature("revokeRole(bytes32,address)",roles[i],old);
        }
        t[8]=address(guard);c[8]=abi.encodeWithSignature("changeGovernor(address)",address(replacement));
        bytes32 salt=bytes32("conditional-governor-replacement");
        safeExec(address(tl),abi.encodeWithSignature("scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)",t,v,c,bytes32(0),salt,0));
        safeExec(address(tl),abi.encodeWithSignature("executeBatch(address[],uint256[],bytes[],bytes32,bytes32)",t,v,c,bytes32(0),salt));
        for(uint256 i=0;i<4;i++){assertTrue(tl.hasRole(roles[i],address(replacement)));assertFalse(tl.hasRole(roles[i],old));}
        gov=replacement;
        pass(address(guard),abi.encodeWithSignature("unpause()"),"review fork only: replacement restores guard");
        assertEq(guard.paused(),1);
    }
}
