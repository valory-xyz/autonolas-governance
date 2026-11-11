// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal17Activation} from "../../scripts/proposals/proposal_17/Proposal17Activation.s.sol";

interface IGovernor {
    function propose(address[] memory, uint256[] memory, bytes[] memory, string memory) external returns (uint256);
    function castVote(uint256, uint8) external returns (uint256);
    function queue(address[] memory, uint256[] memory, bytes[] memory, bytes32) external returns (uint256);
    function execute(address[] memory, uint256[] memory, bytes[] memory, bytes32) external payable returns (uint256);
    function state(uint256) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function proposalEta(uint256) external view returns (uint256);
}

// Measures gas through the real, live GovernorOLAS.execute with the final payload (Pia's check #1),
// with the Timelock pre-funded by the deployer EOA for the retryable values.
// Run: ETH_RPC_URL=<mainnet rpc> forge test --match-contract Proposal17GovernorGas -vv
contract Proposal17GovernorGas is Test {
    address internal constant NEW_GOV  = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS  = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant EOA      = 0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E;
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED  = 7;

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    function test_governorExecuteGas() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        Proposal17Activation p = new Proposal17Activation();
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            p.buildProposal();
        bytes32 dh = keccak256(bytes(description));
        uint256 total;
        for (uint256 i; i < values.length; ++i) total += values[i];

        // Deployer EOA funds the Timelock with the exact retryable total before execution.
        vm.deal(EOA, total + 1 ether);
        vm.prank(EOA);
        (bool funded,) = TIMELOCK.call{value: total}("");
        assertTrue(funded, "EOA could not fund Timelock");

        vm.fee(50 gwei); // the submission-fee ceiling

        IGovernor gov = IGovernor(NEW_GOV);
        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");

        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);
        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);

        // Measure gas through the real Governor.execute (value forwarded from the Timelock's balance).
        uint256 g = gasleft();
        gov.execute(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();

        assertEq(gov.state(id), EXECUTED, "not Executed");

        // Spot-check two Ethereum effects landed through the real path.
        (bool a, bytes memory rv) = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9.staticcall(abi.encodeWithSignature("VERSION()"));
        require(a, "VERSION call failed");
        assertEq(abi.decode(rv, (string)), "1.3.0", "ServiceManager not 1.3.0");
        (bool b, bytes memory rl) = 0x4503b79d468e81Ad2d4bd6Db991810da269bA777.staticcall(abi.encodeWithSignature("numServicesLimit()"));
        require(b, "numServicesLimit call failed");
        assertEq(abi.decode(rl, (uint256)), 44, "numServicesLimit not 44");

        console2.log("Governor.execute() gas used:", executeGas);
        console2.log("EIP-7825 per-tx cap:        ", uint256(16777216));
        assertLt(executeGas, 16777216, "execute exceeds EIP-7825 per-tx gas cap");
    }
}
