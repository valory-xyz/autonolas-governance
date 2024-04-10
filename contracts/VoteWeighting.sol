// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./interfaces/IErrors.sol";

interface IVEOLAS {
    /// @dev Gets the `account`'s lock end time.
    /// @param account Account address.
    /// @return unlockTime Lock end time.
    function lockedEnd(address account) external view returns (uint256 unlockTime);

    /// @dev Gets the most recently recorded user point for `account`.
    /// @param account Account address.
    /// @return pv Last checkpoint.
    function getLastUserPoint(address account) external view returns (PointVoting memory pv);
}

error NomineeDoesNotExist(address nominee, uint256 chainId);
error NomineeAlreadyExists(address nominee, uint256 chainId);
error VoteTooOften(address voter, uint256 curTime, uint256 nextAllowedVotingTime);

struct Point {
    uint256 bias;
    uint256 slope;
}

struct VotedSlope {
    uint256 slope;
    uint256 power;
    uint256 end;
}

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

contract VoteWeighting is IErrors {
    event NewNomineeWeight(address indexed nominee, uint256 chainId, uint256 weight, uint256 totalWeight);
    event VoteForNominee(address indexed user, address indexed nominee, uint256 chainId, uint256 weight);
    event NewNominee(address nominee, uint256 chainId);

    // 7 * 86400 seconds - all future times are rounded by week
    uint256 public constant WEEK = 604800;
    // Cannot change weight votes more often than once in 10 days
    uint256 public constant WEIGHT_VOTE_DELAY = 864000;
    // Max weight amount
    uint256 public constant MAX_WEIGHT = 10000;
    // Maximum chain Id as per EVM specs
    uint256 public constant MAX_CHAIN_ID = type(uint64).max / 2 - 36;
    // veOLAS contract address
    address public immutable ve;

    // TODO: Convert both to cyclic map?
    // Set of (chainId | nominee)
    uint256[] public setNominees;
    // Mapping of (chainId | nominee) => nominee Id
    mapping(uint256 => uint256) public mapNomineeIds;

    // user -> (chainId | nominee) -> VotedSlope
    mapping(address => mapping(uint256 => VotedSlope)) public voteUserSlopes;
    // Total vote power used by user
    mapping(address => uint256) public voteUserPower;
    // Last user vote's timestamp for each (chainId | nominee)
    mapping(address => mapping(uint256 => uint256)) public lastUserVote;

    // Past and scheduled points for nominee weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    // (chainId | nominee) -> time -> Point
    mapping(uint256 => mapping(uint256 => Point)) public pointsWeight;
    // (chainId | nominee) -> time -> slope
    mapping(uint256 => mapping(uint256 => uint256)) public changesWeight;
    // (chainId | nominee) -> last scheduled time (next week)
    mapping(uint256 => uint256) public timeWeight;

    // time -> Point
    mapping(uint256 => Point) public pointsSum;
    // time -> slope
    mapping(uint256 => uint256) public changesSum;
    // last scheduled time (next week)
    uint256 public timeSum;

    /// @dev Contract constructor.
    /// @param _ve `VotingEscrow` contract address.
    constructor(address _ve) {
        // Check for the zero address
        if (_ve == address(0)) {
            revert ZeroAddress();
        }

        // Set initial parameters
        ve = _ve;
        timeSum = block.timestamp / WEEK * WEEK;
        setNominees.push(0);
    }

    /// @dev Fill sum of nominee weights for the same type week-over-week for missed checkins and return the sum for the future week.
    /// @return Sum of weights.
    function _getSum() internal returns (uint256) {
        // t is always > 0 as it is set in the constructor
        uint256 t = timeSum;
        Point memory pt = pointsSum[t];
        for (uint256 i = 0; i < 500; i++) {
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
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @return Nominee weight.
    function _getWeight(address nominee, uint256 chainId) internal returns (uint256) {
        // Push a pair of key defining variables into one key
        // Nominee address and chain Id
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        // Check that the nominee exists
        if (mapNomineeIds[nomineeChainId] == 0) {
            revert NomineeDoesNotExist(nominee, chainId);
        }

        // t is always > 0 as it is set during the addNominee() call
        uint256 t = timeWeight[nomineeChainId];
        Point memory pt = pointsWeight[nomineeChainId][t];
        for (uint256 i = 0; i < 500; i++) {
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            uint256 dBias = pt.slope * WEEK;
            if (pt.bias > dBias) {
                pt.bias -= dBias;
                uint256 dSlope = changesWeight[nomineeChainId][t];
                pt.slope -= dSlope;
            } else {
                pt.bias = 0;
                pt.slope = 0;
            }

            pointsWeight[nomineeChainId][t] = pt;
            if (t > block.timestamp) {
                timeWeight[nomineeChainId] = t;
            }
        }
        return pt.bias;
    }

    /// @dev Add nominee address along with the chain Id.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    function addNominee(address nominee, uint256 chainId) external {
        // Check for the zero address
        if (nominee == address(0)) {
            revert ZeroAddress();
        }

        // Check for the chain Id
        if (chainId == 0) {
            revert ZeroValue();
        }
        else if (chainId > MAX_CHAIN_ID) {
            revert Overflow(chainId, MAX_CHAIN_ID);
        }

        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        // Check for the nominee existence
        if (mapNomineeIds[nomineeChainId] > 0) {
            revert NomineeAlreadyExists(nominee, chainId);
        }
        mapNomineeIds[nomineeChainId] = setNominees.length;
        // Push the nominee into the list
        setNominees.push(nomineeChainId);

        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;
        timeWeight[nomineeChainId] = nextTime;

        emit NewNominee(nominee, chainId);
    }

    /// @dev Checkpoint to fill data common for all nominees.
    function checkpoint() external {
        _getSum();
    }

    /// @dev Checkpoint to fill data for both a specific nominee and common for all nominees.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    function checkpointNominee(address nominee, uint256 chainId) external {
        _getWeight(nominee, chainId);
        _getSum();
    }

    /// @dev Get Nominee relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18).
    ///         Inflation which will be received by it is inflation_rate * relativeWeight / 1e18.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return weight Value of relative weight normalized to 1e18.
    function _nomineeRelativeWeight(address nominee, uint256 chainId, uint256 time) internal view returns (uint256 weight) {
        uint256 t = time / WEEK * WEEK;
        uint256 totalSum = pointsSum[t].bias;

        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        if (totalSum > 0) {
            uint256 nomineeWeight = pointsWeight[nomineeChainId][t].bias;
            weight = 1e18 * nomineeWeight / totalSum;
        }
    }

    /// @dev Get Nominee relative weight (not more than 1.0) normalized to 1e18.
    ///         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    ///         inflation_rate * relativeWeight / 1e18.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function nomineeRelativeWeight(address nominee, uint256 chainId, uint256 time) external view returns (uint256) {
        return _nomineeRelativeWeight(nominee, chainId, time);
    }

    /// @dev Get nominee weight normalized to 1e18 and also fill all the unfilled values for type and nominee records.
    /// @notice Any address can call, however nothing is recorded if the values are filled already.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function nomineeRelativeWeightWrite(address nominee, uint256 chainId, uint256 time) external returns (uint256) {
        _getWeight(nominee, chainId);
        _getSum();
        return _nomineeRelativeWeight(nominee, chainId, time);
    }

    /// @dev Allocate voting power for changing pool weights.
    /// @param nominee Address of the nominee the `msg.sender` votes for.
    /// @param chainId Chain Id.
    /// @param weight Weight for a nominee in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0.
    function voteForNomineeWeights(address nominee, uint256 chainId, uint256 weight) public {
        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        uint256 slope = uint256(uint128(IVEOLAS(ve).getLastUserPoint(msg.sender).slope));
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
        uint256 nextAllowedVotingTime = lastUserVote[msg.sender][nomineeChainId] + WEIGHT_VOTE_DELAY;
        if (nextAllowedVotingTime > block.timestamp) {
            revert VoteTooOften(msg.sender, block.timestamp, nextAllowedVotingTime);
        }

        // Prepare old and new slopes and biases
        VotedSlope memory oldSlope = voteUserSlopes[msg.sender][nomineeChainId];
        uint256 oldBias;
        if (oldSlope.end > nextTime) {
            oldBias = oldSlope.slope * (oldSlope.end - nextTime);
        }

        VotedSlope memory newSlope = VotedSlope({
            slope: slope * weight / MAX_WEIGHT,
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
        pointsWeight[nomineeChainId][nextTime].bias = _maxAndSub(_getWeight(nominee, chainId) + newBias, oldBias);
        pointsSum[nextTime].bias = _maxAndSub(_getSum() + newBias, oldBias);
        if (oldSlope.end > nextTime) {
            pointsWeight[nomineeChainId][nextTime].slope = _maxAndSub(pointsWeight[nomineeChainId][nextTime].slope + newSlope.slope, oldSlope.slope);
            pointsSum[nextTime].slope = _maxAndSub(pointsSum[nextTime].slope + newSlope.slope, oldSlope.slope);
        } else {
            pointsWeight[nomineeChainId][nextTime].slope += newSlope.slope;
            pointsSum[nextTime].slope += newSlope.slope;
        }
        if (oldSlope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changesWeight[nomineeChainId][oldSlope.end] -= oldSlope.slope;
            changesSum[oldSlope.end] -= oldSlope.slope;
        }
        // Add slope changes for new slopes
        changesWeight[nomineeChainId][newSlope.end] += newSlope.slope;
        changesSum[newSlope.end] += newSlope.slope;

        voteUserSlopes[msg.sender][nomineeChainId] = newSlope;

        // Record last action time
        lastUserVote[msg.sender][nomineeChainId] = block.timestamp;

        emit VoteForNominee(msg.sender, nominee, chainId, weight);
    }

    /// @dev Allocate voting power for changing pool weights in batch.
    /// @param nominees Set of nominees the `msg.sender` votes for.
    /// @param chainIds Set of corresponding chain Ids.
    /// @param weights Weights for a nominees in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0.
    function voteForNomineeWeightsBatch(
        address[] memory nominees,
        uint256[] memory chainIds,
        uint256[] memory weights
    ) external {
        if (nominees.length != chainIds.length || nominees.length != weights.length) {
            revert WrongArrayLength(nominees.length, weights.length);
        }

        // Traverse all accounts and weights
        for (uint256 i = 0; i < nominees.length; ++i) {
            voteForNomineeWeights(nominees[i], chainIds[i], weights[i]);
        }
    }

    function _maxAndSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /// @dev Get current nominee weight.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @return Nominee weight.
    function getNomineeWeight(address nominee, uint256 chainId) external view returns (uint256) {
        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        return pointsWeight[nomineeChainId][timeWeight[nomineeChainId]].bias;
    }
    
    /// @dev Get sum of nominee weights.
    /// @return Sum of nominee weights.
    function getWeightsSum() external view returns (uint256) {
        return pointsSum[timeSum].bias;
    }

    /// @dev Get the number of nominees.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @return Total number of nominees.
    function getNumNominees() external view returns (uint256) {
        return setNominees.length - 1;
    }

    /// @dev Gets the nominee Id in the global nominees set.
    /// @param nominee Nominee address.
    /// @param chainId Chain Id.
    /// @return id Nominee Id in the global set of (nominee | chainId) values.
    function getNomineeId(address nominee, uint256 chainId) external view returns (uint256 id) {
        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        id = mapNomineeIds[nomineeChainId];
    }

    /// @dev Get the nominee address and its corresponding chain Id.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @param id Nominee Id in the global set of (nominee | chainId) values.
    /// @return nominee Nominee address.
    /// @return chainId Chain Id.
    function getNominee(uint256 id) external view returns (address nominee, uint256 chainId) {
        // Get the total number of nominees in the contract
        uint256 totalNumNominees = setNominees.length - 1;
        // Check for the zero id or the overflow
        if (id == 0) {
            revert ZeroValue();
        } else if (id > totalNumNominees) {
            revert Overflow(id, totalNumNominees);
        }
        
        uint256 nomineeChainId = setNominees[id];
        // Extract the nominee address
        nominee = address(uint160(uint256(nomineeChainId)));
        // Extract chain Id
        chainId = nomineeChainId >> 160;
    }

    /// @dev Get the set of nominee addresses and corresponding chain Ids.
    /// @notice The zero-th default nominee Id with id == 0 does not count.
    /// @param startId Start Id of the nominee in the global set of (nominee | chainId) values.
    /// @param numNominees Number of nominees to get.
    /// @return nominees Set of nominee addresses.
    /// @return chainIds Set of corresponding chain Ids.
    function getNominees(
        uint256 startId,
        uint256 numNominees
    ) external view returns (address[] memory nominees, uint256[] memory chainIds)
    {
        // Check for the zero id or the overflow
        if (startId == 0 || numNominees == 0) {
            revert ZeroValue();
        }

        // Get the last nominee Id requested
        uint256 endId = startId + numNominees;
        // Get the total number of nominees in the contract with the zero-th nominee
        uint256 totalNumNominees = setNominees.length;

        // Check for the overflow
        if (endId > totalNumNominees) {
            revert Overflow(endId, totalNumNominees);
        }

        // Allocate 
        nominees = new address[](numNominees);
        chainIds = new uint256[](numNominees);

        // Traverse selected nominees
        for (uint256 i = 0; i < numNominees; ++i) {
            uint256 id = i + startId;
            uint256 nomineeChainId = setNominees[id];
            // Extract the nominee address
            nominees[i] = address(uint160(uint256(nomineeChainId)));
            // Extract chain Id
            chainIds[i] = nomineeChainId >> 160;
        }
    }
}