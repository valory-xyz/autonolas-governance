// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal12Builder} from "../../scripts/proposals/proposal_12/Proposal12Unnominate.s.sol";

// Minimal OZ-Governor surface (GovernorOLAS).
interface IGovernor {
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external returns (uint256);
    function execute(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) external payable returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function proposalEta(uint256 proposalId) external view returns (uint256);
}

interface ITimelock { function hasRole(bytes32 role, address account) external view returns (bool); }
interface IVoteWeighting {
    function mapNomineeIds(bytes32 nomineeHash) external view returns (uint256);
    function getNomineeWeight(bytes32 account, uint256 chainId) external view returns (uint256);
    function getWeightsSum() external view returns (uint256);
}

/// @notice Full governance lifecycle (propose -> vote -> queue -> execute) for proposal 12 on a MAINNET fork,
///         through the CURRENTLY-LIVE GovernorOLAS. Asserts every one of the 20 legacy nominees is removed from
///         VoteWeighting and that the kept nominees (LST + the new staking generation) remain live. All 20
///         removeNominee calls are DIRECT L1 calls (VoteWeighting tracks all chains via the chainId arg), so
///         there is NO L2 propagation to simulate for this proposal.
///         Run: forge test --match-contract Proposal12UnnominateTest -vvv
contract Proposal12UnnominateTest is Test, Proposal12Builder {
    address internal constant NEW_GOV = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6; // live GovernorOLAS
    address internal constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300; // gitleaks:allow - public TokenomicsProxy address, not a secret
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant EXECUTED = 7;

    // Kept nominees that MUST survive this proposal untouched.
    address internal constant KEPT_LST = 0x22FA631064A99c43196ec5f8324b73211Ced98f9;      // LST (Gnosis) — carries live weight
    address internal constant KEPT_OMENSTRAT_I = 0x1E215da0541B4a77a66e21F17413A877B84Ab129; // Omenstrat I (Gnosis) — new generation

    /// @dev `Dispenser.removeNominee` reverts Overflow if called within the last week of the ongoing epoch
    ///      (block.timestamp >= epochEnd - 1 week). That is an operational SCHEDULING constraint on when the
    ///      proposal may execute, not a proposal defect. Mock the epoch end so the allowed window is open. In
    ///      production the proposal must simply be executed with > 7 days left in the epoch.
    function _openEpochTimingWindow() internal {
        vm.mockCall(TOKENOMICS, abi.encodeWithSelector(bytes4(keccak256("getEpochEndTime(uint256)"))), abi.encode(block.timestamp));
    }

    function _mockVotes() internal {
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getVotes(address,uint256)"))), abi.encode(uint256(1e28)));
        vm.mockCall(WVEOLAS, abi.encodeWithSelector(bytes4(keccak256("getPastTotalSupply(uint256)"))), abi.encode(uint256(1e24)));
    }

    function _hash(address account, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(bytes32(uint256(uint160(account))), chainId));
    }

    /// @dev Assert every removeNominee actually removed its nominee, and the kept nominees survived.
    function _assertNomineesRemoved(address[] memory targets, bytes[] memory calldatas) internal view {
        uint256 removed;
        for (uint256 i; i < targets.length; ++i) {
            assertEq(targets[i], VOTE_WEIGHTING, "unexpected target");
            bytes memory cd = calldatas[i];
            bytes32 acct; uint256 cid;
            assembly {
                acct := mload(add(cd, 0x24)) // 0x20 (len) + 0x04 (selector) -> account (bytes32)
                cid := mload(add(cd, 0x44)) // next word -> chainId
            }
            bytes32 h = keccak256(abi.encode(acct, cid));
            assertEq(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(h), 0, "nominee not removed");
            removed++;
        }
        assertEq(removed, 20, "expected 20 nominee removals");

        // Kept nominees must remain live.
        assertGt(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(_hash(KEPT_LST, CID_GNOSIS)), 0, "LST must stay nominated");
        assertGt(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(_hash(KEPT_OMENSTRAT_I, CID_GNOSIS)), 0, "Omenstrat I must stay nominated");
    }

    function test_preconditions() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        assertTrue(ITimelock(TIMELOCK).hasRole(PROPOSER_ROLE, NEW_GOV), "NEW_GOV not the live proposer");

        // Every target is a LIVE nominee, and the AGGREGATE vote weight being removed is negligible
        // (< 1% of getWeightsSum) — the weight has already migrated to the new staking generation.
        // (Polymarket Alpha - III carries a known small residual, ~0.23% at drafting time.)
        (address[] memory targets, , bytes[] memory calldatas,) = buildProposal();
        uint256 removedWeight;
        for (uint256 i; i < targets.length; ++i) {
            bytes memory cd = calldatas[i];
            bytes32 acct; uint256 cid;
            assembly {
                acct := mload(add(cd, 0x24))
                cid := mload(add(cd, 0x44))
            }
            assertGt(IVoteWeighting(VOTE_WEIGHTING).mapNomineeIds(keccak256(abi.encode(acct, cid))), 0, "target not a live nominee");
            removedWeight += IVoteWeighting(VOTE_WEIGHTING).getNomineeWeight(acct, cid);
        }
        uint256 sum = IVoteWeighting(VOTE_WEIGHTING).getWeightsSum();
        console2.log("aggregate weight being removed:", removedWeight, " of weightsSum", sum);
        assertLt(removedWeight * 100, sum, "removed targets carry >= 1% of total vote weight");
    }

    function test_L1_fullGovernanceLifecycle() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        _mockVotes();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = buildProposal();
        bytes32 dh = keccak256(bytes(description));
        IGovernor gov = IGovernor(NEW_GOV);

        address proposer = makeAddr("proposer");
        address voter = makeAddr("voter");

        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, description);
        console2.log("proposed id:", id);

        vm.roll(block.number + gov.votingDelay() + 1);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(block.number + gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED, "not Succeeded");

        gov.queue(targets, values, calldatas, dh);
        uint256 eta = gov.proposalEta(id);
        if (eta >= block.timestamp) vm.warp(eta + 1);
        _openEpochTimingWindow(); // mock AFTER warp so it binds to the execution timestamp
        uint256 g = gasleft();
        gov.execute(targets, values, calldatas, dh);
        uint256 executeGas = g - gasleft();
        assertEq(gov.state(id), EXECUTED, "not Executed");

        _assertNomineesRemoved(targets, calldatas);
        console2.log("L1 12 effects asserted: 20 legacy nominees removed; LST + new generation kept");
        console2.log("Governor.execute() gas used:", executeGas);
        console2.log("EIP-7825 per-tx cap:        ", uint256(16777216));
        assertLt(executeGas, 16777216, "execute exceeds EIP-7825 per-tx gas cap");
    }

    /// @dev Fast path: execute directly as the Timelock (no governor), same assertions.
    function test_L1_fullProposal_executesAsTimelock() public {
        vm.createSelectFork(vm.envOr("ETH_RPC", string("https://ethereum-rpc.publicnode.com")));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = buildProposal();

        _openEpochTimingWindow();
        vm.startPrank(TIMELOCK);
        for (uint256 i; i < targets.length; ++i) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) {
                console2.log("reverted at index", i, "target", targets[i]);
                if (ret.length > 0) { assembly { revert(add(ret, 0x20), mload(ret)) } }
                revert("call failed");
            }
        }
        vm.stopPrank();

        _assertNomineesRemoved(targets, calldatas);
    }
}
