// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesCompUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";

/// @title Governor Bravo OLA - Smart contract for the governance
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GovernorBravoOLA is GovernorSettingsUpgradeable, GovernorCompatibilityBravoUpgradeable, GovernorVotesCompUpgradeable, GovernorTimelockControlUpgradeable {
    constructor(ERC20VotesCompUpgradeable _token, TimelockControllerUpgradeable _timelock, uint256 initialVotingDelay,
        uint256 initialVotingPeriod, uint256 initialProposalThreshold) initializer
    {
        // Governor initialization
        __Governor_init("GovernorBravoOLA");
        // Governor initial parameters:
        // Initial voting delay and voting period in number of blocks, initial proposal threshold in voting power weight
        __GovernorSettings_init(initialVotingDelay, initialVotingPeriod, initialProposalThreshold);
        // Bravo compatibility module initialization
        __GovernorCompatibilityBravo_init();
        // Voting weight extraction from an ERC20VotesComp token
        __GovernorVotesComp_init(_token);
        // Timelock related module initialization
        __GovernorTimelockControl_init(_timelock);
    }

    // TODO Verify the return quorum value depending on the tokenomics
    /// @dev Minimum number of cast voted required for a proposal to be successful.
    /// @param blockNumber The snaphot block used for counting vote. This allows to scale the quroum depending on
    ///                    values such as the totalSupply of a token at this block.
    // solhint-disable-next-line
    function quorum(uint256 blockNumber) public pure override returns (uint256) {
        return 1e18;
    }


    /// @dev Current state of a proposal, following Compound’s convention.
    /// @param proposalId Proposal Id.
    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, IGovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }


    // TODO This is a duplicate of propose() function below and must be deleted after JS side works with "propose" name
    // Same with queue, execute functions
    function propose2(address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        string memory description)
        public
        returns (uint256)
    {
        return super.propose(targets, values, calldatas, description);
    }

    /// @dev Create a new proposal to change the protocol / contract parameters.
    /// @param targets The ordered list of target addresses for calls to be made during proposal execution.
    /// @param values The ordered list of values to be passed to the calls made during proposal execution.
    /// @param calldatas The ordered list of data to be passed to each individual function call during proposal execution.
    /// @param description A human readable description of the proposal and the changes it will enact.
    /// @return The Id of the newly created proposal.
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        string memory description)
        public
        override(GovernorUpgradeable, GovernorCompatibilityBravoUpgradeable, IGovernorUpgradeable)
        returns (uint256)
    {
        return super.propose(targets, values, calldatas, description);
    }

    function queue2(address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        bytes32 descriptionHash)
        public
        returns (uint256)
    {
        return super.queue(targets, values, calldatas, descriptionHash);
    }

    /// @dev Gets the number of votes.
    /// @return The number of votes required in order for a voter to become a proposer.
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @dev Executes a proposal.
    /// @param proposalId Proposal Id.
    /// @param targets The ordered list of target addresses.
    /// @param values The ordered list of values.
    /// @param calldatas The ordered list of data to be passed to each individual function call.
    /// @param descriptionHash Hashed description of the proposal.
    function _execute(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        bytes32 descriptionHash)
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
    {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function execute2(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        bytes32 descriptionHash)
        public
    {
        _execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Cancels a proposal.
    /// @param targets The ordered list of target addresses.
    /// @param values The ordered list of values.
    /// @param calldatas The ordered list of data to be passed to each individual function call.
    /// @param descriptionHash Hashed description of the proposal.
    /// @return The Id of the newly created proposal.
    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas,
        bytes32 descriptionHash)
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Gets the executor address.
    /// @return Executor address.
    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    /// @dev Gets information about the interface support.
    /// @param interfaceId A specified interface Id.
    /// @return True if this contract implements the interface defined by interfaceId.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(GovernorUpgradeable, IERC165Upgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
