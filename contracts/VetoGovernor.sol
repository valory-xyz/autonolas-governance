// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Governor, IGovernor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {
    GovernorCompatibilityBravo
} from "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import {GovernorVotes, IVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl, TimelockController} from "./utils/GovernorTimelockControl.sol";

/// @dev This function is permanently disabled on the veto stack.
error Unsupported();

/// @dev Zero address.
error ZeroAddress();

/// @dev A proposal action is not permitted on the veto stack.
/// @param index Index of the offending action.
error ForbiddenAction(uint256 index);

/// @dev The proposal has not been queued through this Governor.
/// @param proposalId Proposal Id.
error NotQueued(uint256 proposalId);

/// @title VetoGovernor - Restricted, cancel-only Governor for the veto stack.
/// @author Valory AG
/// @dev The GovernorOLAS design (OpenZeppelin v4.8.3) with its configuration surface removed. It is a
///      separate contract rather than a subclass because GovernorOLAS finalises its overrides.
/// @notice The veto stack is fixed at deployment: it cannot reconfigure itself or act as itself outside a
///         proposal, and a proposal cannot surrender its cancellation role on the main Timelock.
///         - `setVotingDelay`, `setVotingPeriod`, `setProposalThreshold`, `updateQuorumNumerator`,
///           `updateGovernorDelay`, `updateTimelock` and `relay` are permanently disabled;
///         - `propose` rejects `renounceRole(CANCELLER_ROLE, <veto timelock>)` on the main Timelock;
///         - `execute` only runs a proposal this Governor queued itself.
contract VetoGovernor is
    Governor,
    GovernorSettings,
    GovernorCompatibilityBravo,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // keccak256("CANCELLER_ROLE") - the role the veto stack holds on the main Timelock.
    bytes32 internal constant CANCELLER_ROLE = 0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783;
    // renounceRole(bytes32,address) selector.
    bytes4 internal constant RENOUNCE_ROLE = 0x36568abe;

    // Main Timelock, whose cancellation role the veto stack must keep.
    address public immutable mainTimelock;

    constructor(
        IVotes governanceToken,
        TimelockController timelock,
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 quorumFraction,
        uint256 initialGovernorDelay,
        address _mainTimelock
    )
        Governor("Veto Governor OLAS")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(governanceToken)
        GovernorVotesQuorumFraction(quorumFraction)
        GovernorTimelockControl(timelock, initialGovernorDelay)
    {
        if (_mainTimelock == address(0)) {
            revert ZeroAddress();
        }
        mainTimelock = _mainTimelock;
    }

    // --------------------------------------------------------------------------------------------
    // Veto restrictions
    // --------------------------------------------------------------------------------------------

    /// @dev Permanently disabled.
    function setVotingDelay(uint256) public pure override(GovernorSettings) {
        revert Unsupported();
    }

    /// @dev Permanently disabled.
    function setVotingPeriod(uint256) public pure override(GovernorSettings) {
        revert Unsupported();
    }

    /// @dev Permanently disabled.
    function setProposalThreshold(uint256) public pure override(GovernorSettings) {
        revert Unsupported();
    }

    /// @dev Permanently disabled.
    function updateQuorumNumerator(uint256) external pure override(GovernorVotesQuorumFraction) {
        revert Unsupported();
    }

    /// @dev Permanently disabled.
    function updateTimelock(TimelockController) external pure override(GovernorTimelockControl) {
        revert Unsupported();
    }

    /// @dev Permanently disabled.
    function updateGovernorDelay(uint256) external pure override(GovernorTimelockControl) {
        revert Unsupported();
    }

    /// @dev Permanently disabled: the Governor cannot call arbitrary targets as itself.
    function relay(address, uint256, bytes calldata) external payable override(Governor) {
        revert Unsupported();
    }

    /// @dev Creates a proposal, rejecting any action that surrenders the stack's cancellation role.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(IGovernor, Governor, GovernorCompatibilityBravo) returns (uint256) {
        address vetoTimelock = timelock();
        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] == mainTimelock && _surrendersCanceller(calldatas[i], vetoTimelock)) {
                revert ForbiddenAction(i);
            }
        }
        return super.propose(targets, values, calldatas, description);
    }

    /// @dev True if `data` is `renounceRole(CANCELLER_ROLE, account)`.
    function _surrendersCanceller(bytes memory data, address account) private pure returns (bool) {
        if (data.length < 68) {
            return false;
        }
        bytes4 selector;
        bytes32 role;
        uint256 target;
        assembly {
            selector := mload(add(data, 0x20))
            role := mload(add(data, 0x24))
            target := mload(add(data, 0x44))
        }
        return selector == RENOUNCE_ROLE && role == CANCELLER_ROLE && address(uint160(target)) == account;
    }

    // --------------------------------------------------------------------------------------------
    // Multiple-inheritance resolution (identical to GovernorOLAS)
    // --------------------------------------------------------------------------------------------

    function state(uint256 proposalId)
        public
        view
        override(IGovernor, Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        // The timelock operation is keyed by the batch and its description hash, not by the proposal, so a Succeeded
        // proposal that was never queued here could otherwise execute an identical batch scheduled on the timelock by
        // another proposer. Only a proposal with its own queue record may execute.
        if (proposalEta(proposalId) == 0) {
            revert NotQueued(proposalId);
        }

        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
