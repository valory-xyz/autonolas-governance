// Sources flattened with hardhat v2.17.1 https://hardhat.org
pragma solidity >=0.7.0 <0.9.0;

/// @title Enum - Collection of enums
/// @author Richard Meissner - <richard@gnosis.pm>
contract Enum {
    enum Operation {Call, DelegateCall}
}


// File contracts/multisigs/GuardCM.sol
interface IGovernor {
    function state(uint256 proposalId) external returns (ProposalState);
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
/// @param numValues2 Numberf of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev No delegatecall is allowed.
error NoDelegateCall();

/// @dev No self multisig call is allowed.
error NoSelfCall();

/// @dev The combination of target and selector is not authorized.
/// @param target Target address.
/// @param selector Function selector.
error NotAuthorized(address target, bytes4 selector);

/// @dev The proposal is not defeated.
/// @param proposalId Proposal Id.
/// @param state Current proposal state.
error NotDefeated(uint256 proposalId, ProposalState state);

/// @title GuardCM - Smart contract for Gnosis Safe community multisig (CM) guard
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract GuardCM {
    event GovernorUpdated(address indexed governor);
    event SetTargetSelectors(address[] indexed targets, bytes4[] indexed selectors, bool[] statuses);
    event GovernorCheckProposalIdChanged(uint256 indexed proposalId);
    event GuardPaused(address indexed account);
    event GuardUnpaused();

    // Owner address
    address public immutable owner;
    // Multisig address
    address public immutable multisig;
    // Governor address
    address public governor;
    // Guard pausing possibility
    uint8 public paused = 1;
    
    // Mapping of address + bytes4 selector => enabled / disabled
    mapping(uint256 => bool) public mapAllowedTargetSelectors;

    // Schedule selector
    bytes4 public constant SCHEDULE = bytes4(keccak256(bytes("schedule(address,uint256,bytes,bytes32,bytes32,uint256)")));
    // ScheduleBatch selector
    bytes4 public constant SCHEDULE_BATCH = bytes4(keccak256(bytes("scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)")));
    // Initial check governance proposal Id
    // Calculated from the proposalHash function of the GovernorOLAS with the following parameters:
    // targets = [address(0)], values = [0], calldatas = [0x], description = "Is governance alive?"
    uint256 public governorCheckProposalId = 62151151991217526951504761219057817227643973118811130641152828658327965685127;

    /// @dev GuardCM constructor.
    /// @param _timelock Timelock address.
    /// @param _multisig Community multisig address.
    /// @param _governor Governor address.
    constructor(address _timelock, address _multisig, address _governor) {
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
    function _verifySchedule(bytes memory data, bytes4 selector) internal view {
        //address,uint256,bytes,bytes32,bytes32,uint256
        bytes memory payload = new bytes(data.length - 4);
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
            // Push a pair of key defining variables into one key
            // target occupies first 160 bits
            uint256 targetSelector = uint256(uint160(targets[i]));
            // selector occupies next 32 bits
            targetSelector |= uint256(uint32(bytes4(callDatas[i]))) << 160;

            // Check the authorized combination of target and selector
            if (!mapAllowedTargetSelectors[targetSelector]) {
                revert NotAuthorized(targets[i], bytes4(callDatas[i]));
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
    ) external view {
        // Just return if paused
        if (paused == 1) {
            // Call to the timelock
            if (to == owner) {
                // No delegatecall is allowed
                if (operation == Enum.Operation.DelegateCall) {
                    revert NoDelegateCall();
                }

                // Data length is too short: less than a size of a selector
                if (data.length < 4) {
                    revert IncorrectDataLength(data.length, 4);
                }

                // Get the function signature
                bytes4 functionSig = bytes4(data);
                // Check the schedule or scheduleBatch function authorized parameters
                // All other functions are not checked for
                if (functionSig == SCHEDULE || functionSig == SCHEDULE_BATCH) {
                    _verifySchedule(data, functionSig);
                }
            } else if (to == multisig) {
                // No self multisig call is allowed
                revert NoSelfCall();
            }
        }
    }

    /// @dev Authorizes combinations of targets and selectors.
    /// @param targets Array of target addresses.
    /// @param selectors Array of selectors for targets.
    /// @param statuses Authorize if true, and restrict otherwise.
    function setTargetSelectors(address[] memory targets, bytes4[] memory selectors, bool[] memory statuses) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }
        
        // Check array length
        if (targets.length != selectors.length || targets.length != statuses.length) {
            revert WrongArrayLength(targets.length, selectors.length);
        }

        // Traverse all the targets and selectors to build their paired values
        for (uint256 i = 0; i < targets.length; ++i) {
            // Push a pair of key defining variables into one key
            // target occupies first 160 bits
            uint256 targetSelector = uint256(uint160(targets[i]));
            // selector occupies next 32 bits
            targetSelector |= uint256(uint32(selectors[i])) << 160;

            // Set the status of the target and selector combination
            mapAllowedTargetSelectors[targetSelector] = statuses[i];
        }

        emit SetTargetSelectors(targets, selectors, statuses);
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
}
