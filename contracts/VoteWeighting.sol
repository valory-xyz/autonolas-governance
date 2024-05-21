// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Dispenser interface
interface IDispenser {
    /// @dev Records nominee addition in dispenser.
    /// @param nomineeHash Nominee hash.
    function addNominee(bytes32 nomineeHash) external;

    /// @dev Records nominee removal.
    /// @param nomineeHash Nominee hash.
    function removeNominee(bytes32 nomineeHash) external;
}

// veOLAS interface
interface IVEOLAS {
    // Structure for voting escrow points
    // The struct size is two storage slots of 2 * uint256 (128 + 128 + 64 + 64 + 128)
    struct PointVoting {
        // w(i) = at + b (bias)
        int128 bias;
        // dw / dt = a (slope)
        int128 slope;
        // Timestamp. It will never practically be bigger than 2^64 - 1
        uint64 ts;
        // Block number. It will not be bigger than the timestamp
        uint64 blockNumber;
        // Token amount. It will never practically be bigger. Initial OLAS cap is 1 bn tokens, or 1e27.
        // After 10 years, the inflation rate is 2% per year. It would take 1340+ years to reach 2^128 - 1
        uint128 balance;
    }

    /// @dev Gets the `account`'s lock end time.
    /// @param account Account address.
    /// @return unlockTime Lock end time.
    function lockedEnd(address account) external view returns (uint256 unlockTime);

    /// @dev Gets the most recently recorded user point for `account`.
    /// @param account Account address.
    /// @return pv Last checkpoint.
    function getLastUserPoint(address account) external view returns (PointVoting memory pv);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Value overflow.
/// @param provided Overflow value.
/// @param max Maximum possible value.
error Overflow(uint256 provided, uint256 max);

/// @dev Underflow value.
/// @param provided Provided value.
/// @param expected Minimum expected value.
error Underflow(uint256 provided, uint256 expected);

/// @dev Nominee does not exist.
/// @param account Nominee account address.
/// @param chainId Nominee chain Id.
error NomineeDoesNotExist(bytes32 account, uint256 chainId);

/// @dev Nominee already exists.
/// @param account Nominee account address.
/// @param chainId Nominee chain Id.
error NomineeAlreadyExists(bytes32 account, uint256 chainId);

/// @dev Value lock is expired.
/// @param account Address that is checked for the locked value.
/// @param deadline The lock expiration deadline.
/// @param curTime Current timestamp.
error LockExpired(address account, uint256 deadline, uint256 curTime);

/// @dev Violated a negative slope value.
/// @param account Account address.
/// @param slope Negative slope.
error NegativeSlope(address account, int128 slope);

/// @dev The vote has been performed already.
/// @param voter Voter address.
/// @param curTime Current time.
/// @param nextAllowedVotingTime Next allowed voting time.
error VoteTooOften(address voter, uint256 curTime, uint256 nextAllowedVotingTime);

/// @dev Nominee is not in the removed nominee map.
/// @param account Nominee account address.
/// @param chainId Nominee chain Id.
error NomineeNotRemoved(bytes32 account, uint256 chainId);

/// @dev Nominee is in the removed nominee map.
/// @param account Nominee account address.
/// @param chainId Nominee chain Id.
error NomineeRemoved(bytes32 account, uint256 chainId);

// Point struct
struct Point {
    uint256 bias;
    uint256 slope;
}

// Voted slope struct
struct VotedSlope {
    uint256 slope;
    uint256 power;
    uint256 end;
}

// Nominee struct
struct Nominee {
    bytes32 account;
    uint256 chainId;
}


/// @title VoteWeighting - Smart contract for Vote Weighting with specific nominees composed of address and chain Id
/// @notice Inspired by https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/GaugeController.vy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract VoteWeighting {
    event OwnerUpdated(address indexed owner);
    event DispenserUpdated(address indexed dispenser);
    event Checkpoint(address indexed sender, uint256 sumBias);
    event CheckpointNominee(address indexed sender, bytes32 indexed nomineeAccount, uint256 chainId,
        uint256 nomineeWeight, uint256 totalSum);
    event NomineeRelativeWeightWrite(address indexed sender, bytes32 indexed nomineeAccount, uint256 chainId,
        uint256 nomineeWeight, uint256 totalSum, uint256 relativeWeight);
    event VoteForNominee(address indexed user, bytes32 indexed nominee, uint256 chainId, uint256 weight);
    event AddNominee(bytes32 indexed account, uint256 chainId, uint256 id);
    event RemoveNominee(bytes32 indexed account, uint256 chainId, uint256 newSum);

    // 7 * 86400 seconds - all future times are rounded by week
    uint256 public constant WEEK = 604_800;
    // Cannot change weight votes more often than once in 10 days
    // For explanation about the delay consult the official audit report: https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf
    uint256 public constant WEIGHT_VOTE_DELAY = 864_000;
    // Max number of weeks for checkpoints
    // The number corresponds to slightly more than a year time, that is more than enough to have at least one vote
    // Also, in line with our tokenomics that cannot have epochs longer than a year
    // The suggested maximum amount of weeks results in checkpoint calculation that always fit in the block,
    // although in practice it is unlikely that there is no single checkpoint for the maximum amount of weeks
    // For gas concerns regarding checkpoint calculations, see the internal audit and the official audit report: https://github.com/trailofbits/publications/blob/master/reviews/CurveDAO.pdf
    uint256 public constant MAX_NUM_WEEKS = 53;
    // Max weight amount
    uint256 public constant MAX_WEIGHT = 10_000;
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_EVM_CHAIN_ID = type(uint64).max / 2 - 36;
    // veOLAS contract address
    address public immutable ve;
    // Contract owner address
    address public owner;
    // Dispenser contract
    address public dispenser;

    // Set of Nominee structs
    Nominee[] public setNominees;
    // Set of removed Nominee structs
    Nominee[] public setRemovedNominees;
    // Mapping of hash(Nominee struct) => nominee Id
    mapping(bytes32 => uint256) public mapNomineeIds;
    // Mapping of hash(Nominee struct) => removed nominee Id
    mapping(bytes32 => uint256) public mapRemovedNominees;

    // user -> hash(Nominee struct) -> VotedSlope
    mapping(address => mapping(bytes32 => VotedSlope)) public voteUserSlopes;
    // Total vote power used by user
    mapping(address => uint256) public voteUserPower;
    // Last user vote's timestamp for each hash(Nominee struct)
    mapping(address => mapping(bytes32 => uint256)) public lastUserVote;

    // Past and scheduled points for nominee weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    // hash(Nominee struct) -> time -> Point
    mapping(bytes32 => mapping(uint256 => Point)) public pointsWeight;
    // hash(Nominee struct) -> time -> slope
    mapping(bytes32 => mapping(uint256 => uint256)) public changesWeight;
    // hash(Nominee struct) -> last scheduled time (next week)
    mapping(bytes32 => uint256) public timeWeight;

    // time -> Point
    mapping(uint256 => Point) public pointsSum;
    // time -> slope
    mapping(uint256 => uint256) public changesSum;
    // last scheduled time (next week)
    uint256 public timeSum;

    /// @dev Contract constructor.
    /// @param _ve Voting Escrow contract address.
    constructor(address _ve) {
        // Check for the zero address
        if (_ve == address(0)) {
            revert ZeroAddress();
        }

        // Set initial parameters
        owner = msg.sender;
        ve = _ve;
        timeSum = block.timestamp / WEEK * WEEK;
        // Push empty element to the zero-th index
        setNominees.push(Nominee(0, 0));
        // For symmetry, push empty element to the zero-th index in the removed Nominee set as well
        setRemovedNominees.push(Nominee(0, 0));
    }

    /// @dev Fill sum of nominee weights for the same type week-over-week for missed checkins and return the sum for the future week.
    /// @return Sum of nominee weights.
    function _getSum() internal returns (uint256) {
        // t is always > 0 as it is set in the constructor
        uint256 t = timeSum;
        Point memory pt = pointsSum[t];
        for (uint256 i = 0; i < MAX_NUM_WEEKS; i++) {
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            uint256 dBias = pt.slope * WEEK;
            if (pt.bias > dBias) {
                pt.bias -= dBias;
                uint256 dSlope = changesSum[t];
                pt.slope -= dSlope;
            } else {
                pt.bias = 0;
                pt.slope = 0;
            }

            pointsSum[t] = pt;
            if (t > block.timestamp) {
                timeSum = t;
            }
        }
        return pt.bias;
    }

    /// @dev Fill historic nominee weights week-over-week for missed checkins and return the total for the future week.
    /// @param account Nominee account address in bytes32 form.
    /// @param chainId Nominee chain Id.
    /// @return Nominee weight.
    function _getWeight(bytes32 account, uint256 chainId) internal returns (uint256) {
        // Construct the nominee struct
        Nominee memory nominee = Nominee(account, chainId);

        // Check that the nominee exists or has been removed
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        if (mapRemovedNominees[nomineeHash] == 0 && mapNomineeIds[nomineeHash] == 0) {
            revert NomineeDoesNotExist(account, chainId);
        }

        // t is always > 0 as it is set during the addNominee() call
        uint256 t = timeWeight[nomineeHash];
        Point memory pt = pointsWeight[nomineeHash][t];
        for (uint256 i = 0; i < MAX_NUM_WEEKS; i++) {
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            uint256 dBias = pt.slope * WEEK;
            if (pt.bias > dBias) {
                pt.bias -= dBias;
                uint256 dSlope = changesWeight[nomineeHash][t];
                pt.slope -= dSlope;
            } else {
                pt.bias = 0;
                pt.slope = 0;
            }

            pointsWeight[nomineeHash][t] = pt;
            if (t > block.timestamp) {
                timeWeight[nomineeHash] = t;
            }
        }
        return pt.bias;
    }

    /// @dev Add nominee address along with the chain Id.
    /// @param nominee Nominee account address and chainId.
    function _addNominee(Nominee memory nominee) internal {
        // Check for the nominee existence
        bytes32 nomineeHash = keccak256(abi.encode(nominee));
        if (mapNomineeIds[nomineeHash] > 0) {
            revert NomineeAlreadyExists(nominee.account, nominee.chainId);
        }

        // Check for the previously removed nominee
        if (mapRemovedNominees[nomineeHash] > 0) {
            revert NomineeRemoved(nominee.account, nominee.chainId);
        }

        uint256 id = setNominees.length;
        mapNomineeIds[nomineeHash] = id;
        // Push the nominee into the list
        setNominees.push(nominee);

        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;
        timeWeight[nomineeHash] = nextTime;

        // Enable nominee in dispenser, if applicable
        address localDispenser = dispenser;
        if (localDispenser != address(0)) {
            IDispenser(localDispenser).addNominee(nomineeHash);
        }

        emit AddNominee(nominee.account, nominee.chainId, id);
    }

    /// @dev Add EVM nominee address along with the chain Id.
    /// @param account Address of the nominee.
    /// @param chainId Chain Id.
    function addNomineeEVM(address account, uint256 chainId) external {
        // Check for the zero address
        if (account == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }

        // Check for the chain Id overflow
        if (chainId > MAX_EVM_CHAIN_ID) {
            revert Overflow(chainId, MAX_EVM_CHAIN_ID);
        }

        Nominee memory nominee = Nominee(bytes32(uint256(uint160(account))), chainId);

        // Record nominee instance
        _addNominee(nominee);
    }

    /// @dev Add Non-EVM nominee address along with the chain Id.
    /// @param account Address of the nominee in byte32 standard.
    /// @param chainId Chain Id.
    function addNomineeNonEVM(bytes32 account, uint256 chainId) external {
        // Check for the zero address
        if (account == bytes32(0)) {
            revert ZeroAddress();
        }

        // Check for the chain Id underflow
        if (MAX_EVM_CHAIN_ID >= chainId) {
            revert Underflow(chainId, MAX_EVM_CHAIN_ID + 1);
        }

        Nominee memory nominee = Nominee(account, chainId);

        // Record nominee instance
        _addNominee(nominee);
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes the dispenser contract address.
    /// @notice Dispenser can be set to a zero address if the contract needs to serve a general purpose.
    /// @param newDispenser New dispenser contract address.
    function changeDispenser(address newDispenser) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        dispenser = newDispenser;
        emit DispenserUpdated(newDispenser);
    }

    /// @dev Checkpoints to fill data common for all nominees.
    function checkpoint() external {
        uint256 totalSum = _getSum();

        emit Checkpoint(msg.sender, totalSum);
    }

    /// @dev Checkpoints to fill data for both a specific nominee and common for all nominees.
    /// @param account Address of the nominee.
    /// @param chainId Chain Id.
    function checkpointNominee(bytes32 account, uint256 chainId) external {
        uint256 nomineeWeight = _getWeight(account, chainId);
        uint256 totalSum = _getSum();

        emit CheckpointNominee(msg.sender, account, chainId, nomineeWeight, totalSum);
    }

    /// @dev Gets Nominee relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18) and a sum of weights.
    /// @param account Address of the nominee in byte32 standard.
    /// @param chainId Chain Id.
    /// @param time Timestamp in the past or present.
    /// @return weight Value of relative weight normalized to 1e18.
    /// @return totalSum Sum of nominee weights.
    function _nomineeRelativeWeight(
        bytes32 account,
        uint256 chainId,
        uint256 time
    ) internal view returns (uint256 weight, uint256 totalSum) {
        uint256 t = time / WEEK * WEEK;
        totalSum = pointsSum[t].bias;

        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        if (totalSum > 0) {
            uint256 nomineeWeight = pointsWeight[nomineeHash][t].bias;
            weight = 1e18 * nomineeWeight / totalSum;
        }
    }

    /// @dev Gets Nominee relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18) and a sum of weights.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return relativeWeight Value of nominee relative weight normalized to 1e18.
    /// @return totalSum Sum of nominee weights.
    function nomineeRelativeWeight(
        bytes32 account,
        uint256 chainId,
        uint256 time
    ) external view returns (uint256 relativeWeight, uint256 totalSum) {
        (relativeWeight, totalSum) = _nomineeRelativeWeight(account, chainId, time);
    }

    /// @dev Checkpoints and gets nominee weight normalized to 1e18, and the total sum of all the nominee weights.
    /// @notice Nothing is recorded if the values are already filled.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return relativeWeight Value of nominee relative weight normalized to 1e18.
    /// @return totalSum Sum of nominee weights.
    function nomineeRelativeWeightWrite(
        bytes32 account,
        uint256 chainId,
        uint256 time
    ) external returns (uint256 relativeWeight, uint256 totalSum) {
        uint256 nomineeWeight = _getWeight(account, chainId);
        _getSum();
        (relativeWeight, totalSum) =  _nomineeRelativeWeight(account, chainId, time);

        emit NomineeRelativeWeightWrite(msg.sender, account, chainId, nomineeWeight, totalSum, relativeWeight);
    }

    /// @dev Allocates voting power for changing pool weights.
    /// @param account Address of the nominee the `msg.sender` votes for in bytes32 form.
    /// @param chainId Chain Id.
    /// @param weight Weight for a nominee in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0.
    function voteForNomineeWeights(bytes32 account, uint256 chainId, uint256 weight) public {
        // Get the nominee hash
        bytes32 nomineeHash = keccak256(abi.encode(Nominee(account, chainId)));

        // Check for the previously removed nominee
        if (mapRemovedNominees[nomineeHash] > 0) {
            revert NomineeRemoved(account, chainId);
        }

        // Get user veOLAS slope and check its value
        int128 userSlope = IVEOLAS(ve).getLastUserPoint(msg.sender).slope;
        if (userSlope < 0) {
            revert NegativeSlope(msg.sender, userSlope);
        }

        uint256 lockEnd = IVEOLAS(ve).lockedEnd(msg.sender);
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;

        // Check for the lock end expiration
        if (nextTime >= lockEnd) {
            revert LockExpired(msg.sender, lockEnd, nextTime);
        }

        // Check for the weight number
        if (weight > MAX_WEIGHT) {
            revert Overflow(weight, MAX_WEIGHT);
        }

        // Check for the last voting time
        uint256 nextAllowedVotingTime = lastUserVote[msg.sender][nomineeHash] + WEIGHT_VOTE_DELAY;
        if (nextAllowedVotingTime > block.timestamp) {
            revert VoteTooOften(msg.sender, block.timestamp, nextAllowedVotingTime);
        }

        // Prepare old and new slopes and biases
        VotedSlope memory oldSlope = voteUserSlopes[msg.sender][nomineeHash];
        uint256 oldBias;
        if (oldSlope.end > nextTime) {
            oldBias = oldSlope.slope * (oldSlope.end - nextTime);
        }

        VotedSlope memory newSlope = VotedSlope({
            slope: uint256(uint128(userSlope)) * weight / MAX_WEIGHT,
            end: lockEnd,
            power: weight
        });

        uint256 newBias = newSlope.slope * (lockEnd - nextTime);

        uint256 powerUsed = voteUserPower[msg.sender];
        powerUsed = powerUsed + newSlope.power - oldSlope.power;
        voteUserPower[msg.sender] = powerUsed;
        if (powerUsed > MAX_WEIGHT) {
            revert Overflow(powerUsed, MAX_WEIGHT);
        }

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for nextTime
        pointsWeight[nomineeHash][nextTime].bias = _maxAndSub(_getWeight(account, chainId) + newBias, oldBias);
        pointsSum[nextTime].bias = _maxAndSub(_getSum() + newBias, oldBias);
        if (oldSlope.end > nextTime) {
            pointsWeight[nomineeHash][nextTime].slope =
                _maxAndSub(pointsWeight[nomineeHash][nextTime].slope + newSlope.slope, oldSlope.slope);
            pointsSum[nextTime].slope = _maxAndSub(pointsSum[nextTime].slope + newSlope.slope, oldSlope.slope);
        } else {
            pointsWeight[nomineeHash][nextTime].slope += newSlope.slope;
            pointsSum[nextTime].slope += newSlope.slope;
        }
        if (oldSlope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changesWeight[nomineeHash][oldSlope.end] -= oldSlope.slope;
            changesSum[oldSlope.end] -= oldSlope.slope;
        }
        // Add slope changes for new slopes
        changesWeight[nomineeHash][newSlope.end] += newSlope.slope;
        changesSum[newSlope.end] += newSlope.slope;

        voteUserSlopes[msg.sender][nomineeHash] = newSlope;

        // Record last action time
        lastUserVote[msg.sender][nomineeHash] = block.timestamp;

        emit VoteForNominee(msg.sender, account, chainId, weight);
    }

    /// @dev Allocates voting power for changing pool weights in a batch set.
    /// @param accounts Set of nominee addresses in bytes32 form the `msg.sender` votes for.
    /// @param chainIds Set of corresponding chain Ids.
    /// @param weights Weights for a nominees in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0.
    function voteForNomineeWeightsBatch(
        bytes32[] memory accounts,
        uint256[] memory chainIds,
        uint256[] memory weights
    ) external {
        if (accounts.length != chainIds.length || accounts.length != weights.length) {
            revert WrongArrayLength(accounts.length, weights.length);
        }

        // Traverse all accounts and weights
        for (uint256 i = 0; i < accounts.length; ++i) {
            voteForNomineeWeights(accounts[i], chainIds[i], weights[i]);
        }
    }

    function _maxAndSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /// @dev Removes nominee from the contract and zeros its weight.
    /// @notice The last nominee in the set of nominees is going to change its Id at the end of this function call.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    function removeNominee(bytes32 account, uint256 chainId) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        // Get the nominee id in the nominee set
        uint256 id = mapNomineeIds[nomineeHash];
        if (id == 0) {
            revert NomineeDoesNotExist(account, chainId);
        }

        // Set nominee weight to zero
        uint256 oldWeight = _getWeight(account, chainId);
        uint256 oldSum = _getSum();
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;
        pointsWeight[nomineeHash][nextTime].bias = 0;
        timeWeight[nomineeHash] = nextTime;

        // Account for the the sum weight change
        uint256 newSum = oldSum - oldWeight;
        pointsSum[nextTime].bias = newSum;
        timeSum = nextTime;

        // Add to the removed nominee map and set
        mapRemovedNominees[nomineeHash] = setRemovedNominees.length;
        setRemovedNominees.push(nominee);

        // Remove nominee from the map
        mapNomineeIds[nomineeHash] = 0;

        // Shuffle the current last nominee id in the set to be placed to the removed one
        nominee = setNominees[setNominees.length - 1];
        bytes32 replacedNomineeHash = keccak256(abi.encode(nominee));
        mapNomineeIds[replacedNomineeHash] = id;
        setNominees[id] = nominee;
        // Pop the last element from the set
        setNominees.pop();

        // Remove nominee in dispenser, if applicable
        address localDispenser = dispenser;
        if (localDispenser != address(0)) {
            IDispenser(localDispenser).removeNominee(nomineeHash);
        }

        emit RemoveNominee(account, chainId, newSum);
    }

    /// @dev Revokes user voting power from a removed nominee.
    /// @param account Address of the removed nominee in bytes32 form.
    /// @param chainId Chain Id.
    function revokeRemovedNomineeVotingPower(bytes32 account, uint256 chainId) external {
        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        // Check that the nominee is removed
        if (mapRemovedNominees[nomineeHash] == 0) {
            revert NomineeNotRemoved(account, chainId);
        }

        // Get the user old slope
        VotedSlope memory oldSlope = voteUserSlopes[msg.sender][nomineeHash];
        if (oldSlope.power == 0) {
            revert ZeroValue();
        }

        // Cancel old slope changes if they still didn't happen
        if (oldSlope.end > block.timestamp) {
            changesWeight[nomineeHash][oldSlope.end] -= oldSlope.slope;
            changesSum[oldSlope.end] -= oldSlope.slope;
        }

        // Update the voting power
        uint256 powerUsed = voteUserPower[msg.sender];
        powerUsed = powerUsed - oldSlope.power;
        voteUserPower[msg.sender] = powerUsed;
        delete voteUserSlopes[msg.sender][nomineeHash];
    }

    /// @dev Get current nominee weight.
    /// @param account Address of the nominee in bytes32 form.
    /// @param chainId Chain Id.
    /// @return Nominee weight.
    function getNomineeWeight(bytes32 account, uint256 chainId) external view returns (uint256) {
        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        return pointsWeight[nomineeHash][timeWeight[nomineeHash]].bias;
    }
    
    /// @dev Get sum of nominee weights.
    /// @return Sum of nominee weights.
    function getWeightsSum() external view returns (uint256) {
        return pointsSum[timeSum].bias;
    }

    /// @dev Get the total number of nominees.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @return Total number of nominees.
    function getNumNominees() external view returns (uint256) {
        return setNominees.length - 1;
    }

    /// @dev Get the total number of removed nominees.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @return Total number of removed nominees.
    function getNumRemovedNominees() external view returns (uint256) {
        return setRemovedNominees.length - 1;
    }

    /// @dev Gets a full set of nominees.
    /// @notice The returned set includes the zero-th empty nominee instance.
    /// @return Set of all the nominees in the contract.
    function getAllNominees() external view returns (Nominee[] memory) {
        return setNominees;
    }

    /// @dev Gets a full set of removed nominees.
    /// @notice The returned set includes the zero-th empty nominee instance.
    /// @return Set of all the removed nominees in the contract.
    function getAllRemovedNominees() external view returns (Nominee[] memory) {
        return setRemovedNominees;
    }

    /// @dev Gets the nominee Id in the global nominees set.
    /// @param account Nominee address in bytes32 form.
    /// @param chainId Chain Id.
    /// @return Nominee Id in the global set of Nominee struct values.
    function getNomineeId(bytes32 account, uint256 chainId) external view returns (uint256) {
        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        return mapNomineeIds[nomineeHash];
    }

    /// @dev Gets the removed nominee Id in the global removed nominees set.
    /// @param account Nominee address in bytes32 form.
    /// @param chainId Chain Id.
    /// @return Removed nominee Id in the global set of Nominee struct values.
    function getRemovedNomineeId(bytes32 account, uint256 chainId) external view returns (uint256) {
        // Get the nominee struct and hash
        Nominee memory nominee = Nominee(account, chainId);
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        return mapRemovedNominees[nomineeHash];
    }

    /// @dev Gets the nominee address and its corresponding chain Id.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @param id Nominee Id in the global set of Nominee struct values.
    /// @return Nominee address in bytes32 form and chain Id.
    function getNominee(uint256 id) external view returns (Nominee memory) {
        // Get the total number of nominees in the contract
        uint256 totalNumNominees = setNominees.length - 1;
        // Check for the zero id or the overflow
        if (id == 0) {
            revert ZeroValue();
        } else if (id > totalNumNominees) {
            revert Overflow(id, totalNumNominees);
        }

        return setNominees[id];
    }

    /// @dev Gets the removed nominee address and its corresponding chain Id.
    /// @notice The zero-th default removed nominee Id with id == 0 does not count.
    /// @param id Removed nominee Id in the global set of Nominee struct values.
    /// @return Removed nominee address in bytes32 form and chain Id.
    function getRemovedNominee(uint256 id) external view returns (Nominee memory) {
        // Get the total number of nominees in the contract
        uint256 totalNumRemovedNominees = setRemovedNominees.length - 1;
        // Check for the zero id or the overflow
        if (id == 0) {
            revert ZeroValue();
        } else if (id > totalNumRemovedNominees) {
            revert Overflow(id, totalNumRemovedNominees);
        }

        return setRemovedNominees[id];
    }

    /// @dev Gets next allowed voting time for selected nominees and voters.
    /// @notice The function does not check for repeated nominees and voters.
    /// @param accounts Set of nominee account addresses.
    /// @param chainIds Corresponding set of chain Ids.
    /// @param voters Corresponding set of voters for specified nominees.
    function getNextAllowedVotingTimes(
        bytes32[] memory accounts,
        uint256[] memory chainIds,
        address[] memory voters
    ) external view returns (uint256[] memory nextAllowedVotingTimes) {
        // Check array lengths
        if (accounts.length != chainIds.length || accounts.length != voters.length) {
            revert WrongArrayLength(accounts.length, chainIds.length);
        }

        // Allocate the times array
        nextAllowedVotingTimes = new uint256[](accounts.length);

        // Traverse nominees and get next available voting times
        for (uint256 i = 0; i < accounts.length; ++i) {
            // Get the nominee struct and hash
            Nominee memory nominee = Nominee(accounts[i], chainIds[i]);
            bytes32 nomineeHash = keccak256(abi.encode(nominee));

            // Check for nominee existence
            if (mapNomineeIds[nomineeHash] == 0) {
                revert NomineeDoesNotExist(accounts[i], chainIds[i]);
            }

            // Calculate next allowed voting times
            nextAllowedVotingTimes[i] = lastUserVote[voters[i]][nomineeHash] + WEIGHT_VOTE_DELAY;
        }
    }
}