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
    event OwnerUpdated(address indexed owner);
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
    // Contract owner address
    address public owner;

    // TODO: Convert both to cyclic map
    // Set of (chainId | nominee)
    uint256[] public nomineeAccounts;
    // Mapping of (chainId | nominee)
    mapping(uint256 => bool) public mapNominees;

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

    /// @notice Contract constructor.
    /// @param _ve `VotingEscrow` contract address.
    constructor(address _ve) {
        // Check for the zero address
        if (_ve == address(0)) {
            revert ZeroAddress();
        }

        // Set initial parameters
        owner = msg.sender;
        ve = _ve;
        timeSum = block.timestamp / WEEK * WEEK;
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

    /// @notice Fill sum of nominee weights for the same type week-over-week for missed checkins and return the sum for the future week.
    /// @return Sum of weights.
    function _getSum() internal returns (uint256) {
        uint256 t = timeSum;
        if (t > 0) {
            Point memory pt = pointsSum[t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changesSum[t];
                    pt.slope -= d_slope;
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
        } else {
            return 0;
        }
    }

    /// @notice Fill historic nominee weights week-over-week for missed checkins and return the total for the future week.
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
        if (!mapNominees[nomineeChainId]) {
            revert NomineeDoesNotExist(nominee, chainId);
        }

        uint256 t = timeWeight[nomineeChainId];
        if (t > 0) {
            Point memory pt = pointsWeight[nomineeChainId][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changesWeight[nomineeChainId][t];
                    pt.slope -= d_slope;
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
        } else {
            return 0;
        }
    }

    /// @notice Add nominee address along with the chain Id.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    function addNominee(address nominee, uint256 chainId) external {
        // Check for the zero address
        if (nominee == address(0)) {
            revert ZeroAddress();
        }

        // Check for the chain Id
        if (chainId == 0 || chainId > MAX_CHAIN_ID) {
            revert Overflow(chainId, MAX_CHAIN_ID);
        }

        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        if (mapNominees[nomineeChainId]) {
            revert NomineeAlreadyExists(nominee, chainId);
        }
        mapNominees[nomineeChainId] = true;

        nomineeAccounts.push(nomineeChainId);

        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        if (timeSum == 0) {
            timeSum = next_time;
        }
        timeWeight[nomineeChainId] = next_time;

        emit NewNominee(nominee, chainId);
    }

    /// @notice Checkpoint to fill data common for all nominees.
    function checkpoint() external {
        _getSum();
    }

    /// @notice Checkpoint to fill data for both a specific nominee and common for all nominees.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    function checkpointNominee(address nominee, uint256 chainId) external {
        _getWeight(nominee, chainId);
        _getSum();
    }

    /// @notice Get Nominee relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18).
    ///         Inflation which will be received by it is inflation_rate * relativeWeight / 1e18.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function _nomineeRelativeWeight(address nominee, uint256 chainId, uint256 time) internal view returns (uint256) {
        uint256 t = time / WEEK * WEEK;
        uint256 _totalSum = pointsSum[t].bias;

        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        if (_totalSum > 0) {
            uint256 _nomineeWeight = pointsWeight[nomineeChainId][t].bias;
            return 1e18 * _nomineeWeight / _totalSum;
        } else {
            return 0;
        }
    }

    /// @notice Get Nominee relative weight (not more than 1.0) normalized to 1e18.
    ///         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    ///         inflation_rate * relativeWeight / 1e18.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function nomineeRelativeWeight(address nominee, uint256 chainId, uint256 time) external view returns (uint256) {
        return _nomineeRelativeWeight(nominee, chainId, time);
    }

    /// @notice Get nominee weight normalized to 1e18 and also fill all the unfilled values for type and nominee records.
    /// @dev Any address can call, however nothing is recorded if the values are filled already.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function nomineeRelativeWeightWrite(address nominee, uint256 chainId, uint256 time) external returns (uint256) {
        _getWeight(nominee, chainId);
        _getSum();
        return _nomineeRelativeWeight(nominee, chainId, time);
    }

    // TODO: Supposedly this can only bring weight to zero if something went wrong with the contract
    /// @dev Change weight of `nominee` to `weight`.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param weight New nominee weight.
    function _changeNomineeWeight(address nominee, uint256 chainId, uint256 weight) internal {
        // Change nominee weight
        // Only needed when testing in reality
        uint256 old_nomineeWeight = _getWeight(nominee, chainId);
        uint256 oldSum = _getSum();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        // Push a pair of key defining variables into one key
        // nominee occupies first 160 bits
        uint256 nomineeChainId = uint256(uint160(nominee));
        // chain Id occupies no more than next 64 bits
        nomineeChainId |= chainId << 160;

        pointsWeight[nomineeChainId][next_time].bias = weight;
        timeWeight[nomineeChainId] = next_time;

        uint256 newSum = oldSum + weight - old_nomineeWeight;
        pointsSum[next_time].bias = newSum;
        timeSum = next_time;

        emit NewNomineeWeight(nominee, chainId, weight, newSum);
    }

    // TODO Shall we allow any weight change, or just set it to zero?
    /// @notice Change weight of nominee `addr` to `weight`.
    /// @param nominee Address of the nominee.
    /// @param chainId Chain Id.
    /// @param weight New nominee weight.
    function changeNomineeWeight(address nominee, uint256 chainId, uint256 weight) external {
        require(msg.sender == owner, "Only owner can change nominee weight");
        _changeNomineeWeight(nominee, chainId, weight);
    }

    /// @notice Allocate voting power for changing pool weights.
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
        uint256 lock_end = IVEOLAS(ve).lockedEnd(msg.sender);
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        // TODO: check if next_time == lock_end is ok?
        // Check for the lock end expiration
        if (next_time > lock_end) {
            revert LockExpired(msg.sender, lock_end, next_time);
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
        VotedSlope memory old_slope = voteUserSlopes[msg.sender][nomineeChainId];
        uint256 old_bias;
        if (old_slope.end > next_time) {
            old_bias = old_slope.slope * (old_slope.end - next_time);
        }

        VotedSlope memory new_slope = VotedSlope({
            slope: slope * weight / MAX_WEIGHT,
            end: lock_end,
            power: weight
        });

        uint256 new_bias = new_slope.slope * (lock_end - next_time);

        uint256 power_used = voteUserPower[msg.sender];
        power_used = power_used + new_slope.power - old_slope.power;
        voteUserPower[msg.sender] = power_used;
        if (power_used > MAX_WEIGHT) {
            revert Overflow(power_used, MAX_WEIGHT);
        }

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for next_time
        pointsWeight[nomineeChainId][next_time].bias = _maxAndSub(_getWeight(nominee, chainId) + new_bias, old_bias);
        pointsSum[next_time].bias = _maxAndSub(_getSum() + new_bias, old_bias);
        if (old_slope.end > next_time) {
            pointsWeight[nomineeChainId][next_time].slope = _maxAndSub(pointsWeight[nomineeChainId][next_time].slope + new_slope.slope, old_slope.slope);
            pointsSum[next_time].slope = _maxAndSub(pointsSum[next_time].slope + new_slope.slope, old_slope.slope);
        } else {
            pointsWeight[nomineeChainId][next_time].slope += new_slope.slope;
            pointsSum[next_time].slope += new_slope.slope;
        }
        if (old_slope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changesWeight[nomineeChainId][old_slope.end] -= old_slope.slope;
            changesSum[old_slope.end] -= old_slope.slope;
        }
        // Add slope changes for new slopes
        changesWeight[nomineeChainId][new_slope.end] += new_slope.slope;
        changesSum[new_slope.end] += new_slope.slope;

        voteUserSlopes[msg.sender][nomineeChainId] = new_slope;

        // Record last action time
        lastUserVote[msg.sender][nomineeChainId] = block.timestamp;

        emit VoteForNominee(msg.sender, nominee, chainId, weight);
    }

    /// @notice Allocate voting power for changing pool weights in batch.
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

    /// @notice Get current nominee weight.
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
    
    /// @notice Get sum of nominee weights.
    /// @return Sum of nominee weights.
    function getWeightsSum() external view returns (uint256) {
        return pointsSum[timeSum].bias;
    }
}