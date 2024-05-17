// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import {VerifyData} from "./VerifyData.sol";

interface IGovernor {
    function state(uint256 proposalId) external returns (ProposalState);
}

interface IBridgeVerifier {
    /// @dev Processes bridged data: checks the header and verifies the payload.
    /// @param data Full data bytes with the header.
    /// @param bridgeMediatorL2 Address of a bridged mediator on L2.
    /// @param chainId L2 chain Id.
    function processBridgeData(
        bytes memory data,
        address bridgeMediatorL2,
        uint256 chainId
    ) external;
}

// Governor proposal state
enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

// Struct for bridge parameters
struct BridgeParams {
    // Data verifier contract for calls executed on L2
    address verifierL2;
    // Bridge mediator (data receiving) contract on L2
    address bridgeMediatorL2;
    // Chain Id: this value cannot practically be bigger than `floor(MAX_UINT64 / 2) - 36` as per EIP 2294
    uint64 chainId;
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as an owner.
error ManagerOnly(address sender, address manager);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of of values in a second array.
/// @param numValues3 Number of of values in a third array.
/// @param numValues4 Number of of values in a fourth array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2, uint256 numValues3, uint256 numValues4);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev No delegatecall is allowed.
error NoDelegateCall();

/// @dev No self multisig call is allowed.
error NoSelfCall();

/// @dev The proposal is not defeated.
/// @param proposalId Proposal Id.
/// @param state Current proposal state.
error NotDefeated(uint256 proposalId, ProposalState state);

/// @dev Delegatecall reverted.
error DelegateCallFailed();

/// @dev Only the contract address is allowed, but the EOA account was provided.
/// @param account Account address.
error ContractOnly(address account);

/// @dev Passed L2 chain Id is not supported.
/// @param chainId L2 chain Id.
error L2ChainIdNotSupported(uint256 chainId);

/// @title GuardCM - Smart contract for Gnosis Safe community multisig (CM) guard
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract GuardCM is VerifyData {
    event GovernorUpdated(address indexed governor);
    event SetTargetSelectors(address[] indexed targets, bytes4[] indexed selectors, uint256[] chainIds, bool[] statuses);
    event SetBridgeMediators(address[] indexed bridgeMediatorL1s, address[] indexed verifierL2s,
        address[] indexed bridgeMediatorL2s, uint256[] chainIds);
    event GovernorCheckProposalIdChanged(uint256 indexed proposalId);
    event GuardPaused(address indexed account);
    event GuardUnpaused();

    // schedule selector
    bytes4 public constant SCHEDULE = bytes4(keccak256(bytes("schedule(address,uint256,bytes,bytes32,bytes32,uint256)")));
    // scheduleBatch selector
    bytes4 public constant SCHEDULE_BATCH = bytes4(keccak256(bytes("scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)")));
    // requireToPassMessage selector (Gnosis chain)
    // Initial check governance proposal Id
    // Calculated from the proposalHash function of the GovernorOLAS
    uint256 public governorCheckProposalId = 88250008686885504216650933897987879122244685460173810624866685274624741477673;
    // Minimum data length that is encoded for the schedule function,
    // plus at least 4 bytes or 32 bits for the selector from the payload
    uint256 public constant MIN_SCHEDULE_DATA_LENGTH = 260;
    // Minimum data length that contains at least a selector (4 bytes or 32 bits)
    uint256 public constant SELECTOR_DATA_LENGTH = 4;
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;

    // Owner address
    address public immutable owner;
    // Multisig address
    address public immutable multisig;

    // Governor address
    address public governor;
    // Guard pausing possibility
    uint8 public paused = 1;

    // Mapping of L1 bridge mediator => (L2 verifier | uint64 supported L2 chain Id | L2 bridge mediator)
    mapping(address => BridgeParams) public mapBridgeMediatorL1BridgeParams;

    /// @dev GuardCM constructor.
    /// @param _timelock Timelock address.
    /// @param _multisig Community multisig address.
    /// @param _governor Governor address.
    constructor(
        address _timelock,
        address _multisig,
        address _governor
    ) {
        // Check for zero addresses
        if (_timelock == address(0) || _multisig == address(0) || _governor == address(0)) {
            revert ZeroAddress();
        }
        owner = _timelock;
        multisig = _multisig;
        governor = _governor;
    }

    /// @dev Changes the governor.
    /// @param newGovernor Address of a new governor.
    function changeGovernor(address newGovernor) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newGovernor == address(0)) {
            revert ZeroAddress();
        }

        governor = newGovernor;
        emit GovernorUpdated(newGovernor);
    }

    /// @dev Changes the governor check proposal Id.
    /// @param proposalId Governor check proposal Id.
    function changeGovernorCheckProposalId(uint256 proposalId) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero value
        if (proposalId == 0) {
            revert ZeroValue();
        }

        governorCheckProposalId = proposalId;
        emit GovernorCheckProposalIdChanged(proposalId);
    }

    /// @dev Verifies authorized target and selector in the schedule or scheduleBatch function call.
    /// @param data Data in bytes.
    /// @param selector Schedule function selector.
    function _verifySchedule(bytes memory data, bytes4 selector) internal {
        // Copy the data without the selector
        bytes memory payload = new bytes(data.length - SELECTOR_DATA_LENGTH);
        for (uint256 i = 0; i < payload.length; ++i) {
            payload[i] = data[i + 4];
        }

        // Prepare the decoding data sets
        address[] memory targets;
        bytes[] memory callDatas;
        if (selector == SCHEDULE) {
            targets = new address[](1);
            callDatas = new bytes[](1);
            // Decode the data in the schedule function
            (targets[0], , callDatas[0], , , ) =
                abi.decode(payload, (address, uint256, bytes, bytes32, bytes32, uint256));
        } else {
            // Decode the data in the scheduleBatch function
            (targets, , callDatas, , , ) =
            abi.decode(payload, (address[], uint256[], bytes[], bytes32, bytes32, uint256));
        }

        // Traverse all the schedule targets and selectors extracted from calldatas
        for (uint i = 0; i < targets.length; ++i) {
            // Get the verifierL2 and L2 chain Id, if any
            BridgeParams memory bridgeParams = mapBridgeMediatorL1BridgeParams[targets[i]];

            // Check if the data goes across the bridge
            if (bridgeParams.verifierL2 != address(0)) {
                // Process the bridge logic
                bytes memory processData = abi.encodeCall(IBridgeVerifier.processBridgeData, (callDatas[i],
                    bridgeParams.bridgeMediatorL2, bridgeParams.chainId));
                (bool success, bytes memory returnData) = bridgeParams.verifierL2.delegatecall(processData);
                // Process unsuccessful delegatecall
                if (!success) {
                    // Get the revert message bytes
                    if (returnData.length > 0) {
                        assembly {
                            let returnDataSize := mload(returnData)
                            revert(add(32, returnData), returnDataSize)
                        }
                    } else {
                        revert DelegateCallFailed();
                    }
                }
            } else {
                // Verify the data right away as it is not the bridged one
                _verifyData(targets[i], callDatas[i], block.chainid);
            }
        }
    }

    /// @dev Checks the transaction for authorized arguments.
    /// @notice Scheduling in timelock is checked against authorized targets and signatures.
    /// @notice No self-multisig function calls are allowed.
    /// @param to Destination address of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    function checkTransaction(
        address to,
        uint256,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external {
        // Just return if paused
        if (paused == 1) {
            // No delegatecall is allowed
            if (operation == Enum.Operation.DelegateCall) {
                revert NoDelegateCall();
            }

            // Call to the timelock
            if (to == owner) {
                // Data needs to have enough bytes at least to fit the selector
                if (data.length < SELECTOR_DATA_LENGTH) {
                    revert IncorrectDataLength(data.length, SELECTOR_DATA_LENGTH);
                }

                // Get the function signature
                bytes4 functionSig = bytes4(data);
                // Check the schedule or scheduleBatch function authorized parameters
                // All other functions are not checked for
                if (functionSig == SCHEDULE || functionSig == SCHEDULE_BATCH) {
                    // Data length is too short: need to have enough bytes for the schedule() function
                    // with one selector extracted from the payload
                    if (data.length < MIN_SCHEDULE_DATA_LENGTH) {
                        revert IncorrectDataLength(data.length, MIN_SCHEDULE_DATA_LENGTH);
                    }

                    _verifySchedule(data, functionSig);
                }
            } else if (to == multisig) {
                // No self multisig call is allowed
                revert NoSelfCall();
            }
        }
    }

    /// @dev Authorizes combinations of targets, selectors and chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 chain Ids where the contract is deployed
    ///         and corresponding supported L2-s, if the contract interacts with them.
    /// @param targets Array of target addresses.
    /// @param selectors Array of selectors for targets.
    /// @param chainIds Chain Ids for authorized functions.
    /// @param statuses Authorize if true, and restrict otherwise.
    function setTargetSelectorChainIds(
        address[] memory targets,
        bytes4[] memory selectors,
        uint256[] memory chainIds,
        bool[] memory statuses
    ) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        // Check array length
        if (targets.length != selectors.length || targets.length != statuses.length || targets.length != chainIds.length) {
            revert WrongArrayLength(targets.length, selectors.length, statuses.length, chainIds.length);
        }

        // Traverse all the targets and selectors to build their paired values
        for (uint256 i = 0; i < targets.length; ++i) {
            // Check for zero address targets
            if (targets[i] == address(0)) {
                revert ZeroAddress();
            }

            // Check selector for zero selector value
            if (selectors[i] == bytes4(0)) {
                revert ZeroValue();
            }

            // Check chain Ids to be greater than zero
            if (chainIds[i] == 0) {
                revert ZeroValue();
            }

            // Push a pair of key defining variables into one key
            // target occupies first 160 bits
            uint256 targetSelectorChainId = uint256(uint160(targets[i]));
            // selector occupies next 32 bits
            targetSelectorChainId |= uint256(uint32(selectors[i])) << 160;
            // chainId occupies next 64 bits
            targetSelectorChainId |= chainIds[i] << 192;

            // Set the status of the target and selector combination
            mapAllowedTargetSelectorChainIds[targetSelectorChainId] = statuses[i];
        }

        emit SetTargetSelectors(targets, selectors, chainIds, statuses);
    }

    /// @dev Sets bridge mediator and L2 verifier contracts addresses on L1 and L2 chain Ids.
    /// @notice It is the contract owner responsibility to set correct L1 bridge mediator contracts,
    ///         corresponding L2 verifier contracts, and supported chain Ids.
    ///         Note that it is out of scope of the verification procedure to check if any other chain Id formats,
    ///         like Wormhole one, is correctly setup during the bridge call.
    /// @param bridgeMediatorL1s Bridge mediator contract addresses on L1.
    /// @param verifierL2s Corresponding L2 verifier contract addresses on L1.
    /// @param chainIds Corresponding L2 chain Ids (original EVM numbers).
    /// @param bridgeMediatorL2s Corresponding L2 bridge mediators.
    function setBridgeMediatorL1BridgeParams(
        address[] memory bridgeMediatorL1s,
        address[] memory verifierL2s,
        uint256[] memory chainIds,
        address[] memory bridgeMediatorL2s
    ) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for array correctness
        if (bridgeMediatorL1s.length != verifierL2s.length || bridgeMediatorL1s.length != chainIds.length ||
            bridgeMediatorL1s.length != bridgeMediatorL2s.length) {
            revert WrongArrayLength(bridgeMediatorL1s.length, verifierL2s.length, chainIds.length, bridgeMediatorL2s.length);
        }

        // Link L1 and L2 bridge mediators, set L2 chain Ids and L2 verifiers
        for (uint256 i = 0; i < chainIds.length; ++i) {
            // Check for zero addresses
            // Note that bridgeMediatorL2-s can be zero addresses, for example, for Arbitrum case
            if (bridgeMediatorL1s[i] == address(0) || verifierL2s[i] == address(0)) {
                revert ZeroAddress();
            }

            // Check that the verifier is a contract
            if (verifierL2s[i].code.length == 0) {
                revert ContractOnly(verifierL2s[i]);
            }

            // Check chain Id
            uint256 chainId = chainIds[i];
            if (chainId == 0 || chainId > MAX_CHAIN_ID) {
                revert L2ChainIdNotSupported(chainId);
            }
            
            // Set bridge params
            BridgeParams storage bridgeParams = mapBridgeMediatorL1BridgeParams[bridgeMediatorL1s[i]];
            bridgeParams.verifierL2 = verifierL2s[i];
            bridgeParams.bridgeMediatorL2 = bridgeMediatorL2s[i];
            bridgeParams.chainId = uint64(chainIds[i]);
        }
        emit SetBridgeMediators(bridgeMediatorL1s, verifierL2s, bridgeMediatorL2s, chainIds);
    }

    /// @dev Pauses the guard restoring a full CM functionality.
    /// @notice The timeline is able to pause the guard via the voting.
    /// @notice The CM can request pausing the guard is there was a proposal to check if the governance is alive.
    ///         If the proposal is defeated (not enough votes or never voted on),
    ///         the governance is considered inactive for about a week.
    function pause() external {
        if (msg.sender == owner) {
            // Timelock can release the community multisig right away
            paused = 2;
        } else if (msg.sender == multisig) {
            // Multisig needs to check if the governor check proposal Id state is defeated
            ProposalState state = IGovernor(governor).state(governorCheckProposalId);
            if (state == ProposalState.Defeated) {
                paused = 2;
            } else {
                revert NotDefeated(governorCheckProposalId, state);
            }
        } else {
            // msg.sender is not a timelock, nor a multisig
            revert ManagerOnly(msg.sender, multisig);
        }

        emit GuardPaused(msg.sender);
    }

    /// @dev Unpauses the guard restricting the CM functionality back.
    function unpause() external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;

        emit GuardUnpaused();
    }

    /// @dev Guards the multisig call after its execution.
    function checkAfterExecution(bytes32, bool) external {}

    /// @dev Gets the status of a target-selector-chainId combination.
    /// @param target Target address.
    /// @param selector Selector for a target.
    /// @param chainId Corresponding chain Id.
    /// @return status True, if the target-selector-chainId combination is authorized.
    function getTargetSelectorChainId(address target, bytes4 selector, uint256 chainId) external view
        returns (bool status)
    {
        // Push a pair of key defining variables into one key
        // target occupies first 160 bits
        uint256 targetSelectorChainId = uint256(uint160(target));
        // selector occupies next 32 bits
        targetSelectorChainId |= uint256(uint32(selector)) << 160;
        // chainId occupies next 64 bits
        targetSelectorChainId |= chainId << 192;

        status = mapAllowedTargetSelectorChainIds[targetSelectorChainId];
    }
}