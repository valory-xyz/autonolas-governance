// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal15GovernorParams} from "../../scripts/proposals/proposal_15/Proposal15GovernorParams.s.sol";

/// @notice Proposal 15 — raise `proposalThreshold` to 250,000 veOLAS and the quorum numerator to 10.
///
///         The builder's bytes and id are asserted in a view-only test, so that assertion stays valid
///         after the proposal is submitted. The lifecycle runs on a rehearsal description: proposing the
///         published bytes on a fork would revert `Governor: proposal already exists` from the moment the
///         real proposal is on-chain, and this suite is meant to be re-run immediately before execution.
///
///         Run: ETH_RPC_URL=<rpc> forge test --match-contract Proposal15 -vv
interface IGovernor {
    function propose(address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
        external
        returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function cancel(uint256 proposalId) external;
    function queue(address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 dh) external returns (uint256);
    function execute(address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 dh)
        external
        payable
        returns (uint256);
    function hashProposal(address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 dh)
        external
        pure
        returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function proposalEta(uint256 proposalId) external view returns (uint256);
    function proposalSnapshot(uint256 proposalId) external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function quorum(uint256 blockNumber) external view returns (uint256);
    function quorumNumerator() external view returns (uint256);
    function quorumNumerator(uint256 blockNumber) external view returns (uint256);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
    function governorDelay() external view returns (uint256);
    function getVotes(address account, uint256 blockNumber) external view returns (uint256);
}

contract Proposal15GovernorParamsTest is Test {
    address internal constant GOVERNOR = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6;
    /// @dev Rank-1 veOLAS holder: clears both the live and the proposed threshold, and quorum alone.
    address internal constant WHALE = 0x063923C9b00Bd1eFb1EF5a89498538F5A1237a97;
    /// @dev The address that has created every DAO proposal to date.
    address internal constant DAO_PROPOSER = 0x34471096285C2B59164E20c03f6977423a450039;

    uint256 internal constant PUBLISHED_ID =
        3563000702947626407249966116394330391891319244018918786718598572660765109424;
    bytes32 internal constant PUBLISHED_DESCRIPTION_HASH =
        0xbc86418e14715cfad78c62576109d9825e2b1b7395fb5f3a594cc64eef35f8b1;

    string internal constant REHEARSAL = "proposal 15 lifecycle rehearsal - not for submission";

    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant QUEUED = 5;
    uint8 internal constant EXECUTED = 7;
    uint8 internal constant FOR = 1;

    Proposal15GovernorParams internal builder;
    IGovernor internal gov = IGovernor(GOVERNOR);

    function setUp() public {
        // Fork first, then deploy the builder into it: creating a fork later would discard a builder
        // deployed against the pre-fork state and every call to it would revert.
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        builder = new Proposal15GovernorParams();
    }

    function _mine(uint256 n) internal {
        vm.roll(block.number + n);
        vm.warp(block.timestamp + n * 12);
    }

    /// @notice The bytes that will be submitted, and the id they produce.
    function testBuilderBytesAndPublishedId() public view {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = builder.buildProposal();

        assertEq(t.length, 2);
        assertEq(t[0], GOVERNOR);
        assertEq(t[1], GOVERNOR);
        assertEq(v[0], 0);
        assertEq(v[1], 0);
        assertEq(c[0], abi.encodeWithSignature("setProposalThreshold(uint256)", uint256(250_000e18)));
        assertEq(c[1], abi.encodeWithSignature("updateQuorumNumerator(uint256)", uint256(10)));

        assertEq(keccak256(bytes(d)), PUBLISHED_DESCRIPTION_HASH, "descriptionHash");
        assertEq(
            uint256(keccak256(abi.encode(t, v, c, keccak256(bytes(d))))), PUBLISHED_ID, "proposalId"
        );
    }

    /// @notice The description carries the DAO Constitution reference every proposal ends with.
    function testDescriptionCarriesTheDaoSignature() public view {
        (,,, string memory d) = builder.buildProposal();
        bytes memory b = bytes(d);
        bytes memory sig = bytes(
            "In accordance with Autonolas DAO Constitution at"
            " ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u"
        );
        assertGt(b.length, sig.length);
        bytes memory tail = new bytes(sig.length);
        for (uint256 i = 0; i < sig.length; ++i) {
            tail[i] = b[b.length - sig.length + i];
        }
        assertEq(keccak256(tail), keccak256(sig), "description must end with the DAO signature");
    }

    function testLifecycleAndPostConditions() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c,) = builder.buildProposal();
        bytes32 dh = keccak256(bytes(REHEARSAL));

        assertEq(gov.proposalThreshold(), 5_000e18, "starting threshold");
        assertEq(gov.quorumNumerator(), 3, "starting numerator");
        // The cap that makes this safe: the new threshold must stay below the power of the address that
        // creates the DAO's proposals, or Bravo's permissionless cancel opens on the DAO's own proposals.
        assertGt(gov.getVotes(DAO_PROPOSER, block.number - 1), 250_000e18, "250k stays under the DAO proposer");

        vm.prank(WHALE);
        uint256 id = gov.propose(t, v, c, REHEARSAL);

        _mine(gov.votingDelay() + 1);
        vm.prank(WHALE);
        uint256 weight = gov.castVote(id, FOR);
        assertGt(weight, gov.quorum(gov.proposalSnapshot(id)), "one holder clears quorum");

        _mine(gov.votingPeriod() + 1);
        assertEq(gov.state(id), SUCCEEDED);

        gov.queue(t, v, c, dh);
        assertEq(gov.state(id), QUEUED);
        assertEq(gov.proposalEta(id), block.timestamp + gov.governorDelay(), "eta is queue + governorDelay");

        vm.warp(gov.proposalEta(id) + 1);
        vm.roll(block.number + gov.governorDelay() / 12 + 1);
        gov.execute(t, v, c, dh);

        assertEq(gov.state(id), EXECUTED);
        assertEq(gov.proposalThreshold(), 250_000e18, "threshold raised");
        assertEq(gov.quorumNumerator(), 10, "numerator raised");

        // The numerator is checkpointed: anything already snapshotted keeps 3%.
        assertEq(gov.quorumNumerator(gov.proposalSnapshot(id)), 3, "the in-flight bar is unchanged");
        _mine(1);
        assertEq(gov.quorumNumerator(block.number - 1), 10, "10% binds from the execution block");
    }
}
