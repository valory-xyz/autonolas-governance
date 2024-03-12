// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./interfaces/IErrors.sol";

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

contract VoteWeighting is IErrors {
    event OwnerUpdated(address indexed owner);
    event NewTypeWeight(uint256 time, uint256 weight, uint256 total_weight);
    event NewGaugeWeight(address indexed gauge_address, uint256 time, uint256 weight, uint256 total_weight);
    event VoteForGauge(uint256 time, address indexed user, address indexed gauge_addr, uint256 weight);
    event NewGauge(address addr, uint256 weight);

    // 7 * 86400 seconds - all future times are rounded by week
    uint256 public constant WEEK = 604800;

    // Cannot change weight votes more often than once in 10 days
    uint256 public constant WEIGHT_VOTE_DELAY = 10 * 86400;
    uint256 public constant MULTIPLIER = 10 ** 18;

    address public immutable ve; // Voting escrow

    address public owner;  // Can and will be a smart contract

    // Gauge parameters
    // All numbers are "fixed point" on the basis of 1e18
    uint256 public n_gauges;

    // Needed for enumeration
    address[1000000000] public gauges;

    mapping(address => mapping(address => VotedSlope)) public vote_user_slopes;  // user -> gauge_addr -> VotedSlope
    mapping(address => uint256) public vote_user_power;  // Total vote power used by user
    mapping(address => mapping(address => uint256)) public last_user_vote;  // Last user vote's timestamp for each gauge address

    // Past and scheduled points for gauge weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    mapping(address => mapping(uint256 => Point)) public points_weight;  // gauge_addr -> time -> Point
    mapping(address => mapping(uint256 => uint256)) public changes_weight;  // gauge_addr -> time -> slope
    mapping(address => uint256) public time_weight;  // gauge_addr -> last scheduled time (next week)

    mapping(uint256 => Point) public points_sum;  // time -> Point
    mapping(uint256 => uint256) public changes_sum;  // time -> slope
    uint256 public time_sum; // last scheduled time (next week)

    mapping(uint256 => uint256) public points_total; // time -> total weight
    uint256 public time_total;  // last scheduled time

    mapping(uint256 => uint256) public points_type_weight; // time -> type weight
    uint256 public time_type_weight;  // last scheduled time (next week)

    /// @notice Contract constructor.
    /// @param _ve `VotingEscrow` contract address.
    constructor(address _ve) {
        if (_ve != address(0)) {
            revert ZeroAddress();
        }

        owner = msg.sender;
        ve = _ve;
        time_total = block.timestamp / WEEK * WEEK;
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

    /// @notice Fill historic type weights week-over-week for missed checkins and return the type weight for the future week.
    /// @return Type weight.
    function _get_type_weight() internal returns (uint256) {
        uint256 t = time_type_weight;
        if (t > 0) {
            uint256 w = points_type_weight[t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                points_type_weight[t] = w;
                if (t > block.timestamp) {
                    time_type_weight = t;
                }
            }
            return w;
        } else {
            return 0;
        }
    }

    /// @notice Fill sum of gauge weights for the same type week-over-week for missed checkins and return the sum for the future week.
    /// @return Sum of weights.
    function _get_sum() internal returns (uint256) {
        uint256 t = time_sum;
        if (t > 0) {
            // TODO: Memory or storage?
            Point memory pt = points_sum[t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changes_sum[t];
                    pt.slope -= d_slope;
                } else {
                    pt.bias = 0;
                    pt.slope = 0;
                }
                // TODO: ensure to have a deep copy
                points_sum[t] = pt;
                if (t > block.timestamp) {
                    time_sum = t;
                }
            }
            return pt.bias;
        } else {
            return 0;
        }
    }

    /// @notice Fill historic total weights week-over-week for missed checkins and return the total for the future week.
    /// @return Total weight.
    function _get_total() internal returns (uint256) {
        uint256 t = time_total;

        if (t > block.timestamp) {
            // If we have already checkpointed - still need to change the value
            t -= WEEK;
        }

        uint256 pt = points_total[t];

        _get_sum();
        _get_type_weight();

        for (uint256 i = 0; i < 500; i++) {
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            pt = 0;

            uint256 type_sum = points_sum[t].bias;
            uint256 type_weight = points_type_weight[t];
            pt = type_sum * type_weight;

            points_total[t] = pt;

            if (t > block.timestamp) {
                time_total = t;
            }
        }
        return pt;
    }

    /// @notice Fill historic gauge weights week-over-week for missed checkins and return the total for the future week.
    /// @param gauge_addr Address of the gauge.
    /// @return Gauge weight.
    function _get_weight(address gauge_addr) internal returns (uint256) {
        uint256 t = time_weight[gauge_addr];
        if (t > 0) {
            Point memory pt = points_weight[gauge_addr][t];
            for (uint256 i = 0; i < 500; i++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 d_bias = pt.slope * WEEK;
                if (pt.bias > d_bias) {
                    pt.bias -= d_bias;
                    uint256 d_slope = changes_weight[gauge_addr][t];
                    pt.slope -= d_slope;
                } else {
                    pt.bias = 0;
                    pt.slope = 0;
                }
                // TODO: Make sure about deep copy
                points_weight[gauge_addr][t] = pt;
                if (t > block.timestamp) {
                    time_weight[gauge_addr] = t;
                }
            }
            return pt.bias;
        } else {
            return 0;
        }
    }

    /// @notice Add gauge `addr` of type `gauge_type` with weight `weight`.
    /// @param addr Gauge address.
    /// @param weight Gauge weight.
    function add_gauge(address addr, uint256 weight) external {
        require(msg.sender == owner, "Only owner can add gauge");
        // TODO: Check that the addr was not added before?
        //require(gauge_types_[addr] == 0, "Cannot add the same gauge twice");

        uint256 n = n_gauges;
        n_gauges = n + 1;
        gauges[n] = addr;

        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        if (weight > 0) {
            uint256 _type_weight = _get_type_weight();
            uint256 _old_sum = _get_sum();
            uint256 _old_total = _get_total();

            points_sum[next_time].bias = weight + _old_sum;
            time_sum = next_time;
            points_total[next_time] = _old_total + _type_weight * weight;
            time_total = next_time;

            points_weight[addr][next_time].bias = weight;
        }

        if (time_sum == 0) {
            time_sum = next_time;
        }
        time_weight[addr] = next_time;

        emit NewGauge(addr, weight);
    }

    /// @notice Checkpoint to fill data common for all gauges.
    function checkpoint() external {
        _get_total();
    }

    /// @notice Checkpoint to fill data for both a specific gauge and common for all gauges.
    /// @param addr Gauge address.
    function checkpoint_gauge(address addr) external {
        _get_weight(addr);
        _get_total();
    }

    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18).
    ///         Inflation which will be received by it is inflation_rate * relative_weight / 1e18.
    /// @param addr Gauge address.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function _gauge_relative_weight(address addr, uint256 time) internal view returns (uint256) {
        uint256 t = time / WEEK * WEEK;
        uint256 _total_weight = points_total[t];

        if (_total_weight > 0) {
            // TODO: Do we need _type_weight?
            uint256 _type_weight = points_type_weight[t];
            uint256 _gauge_weight = points_weight[addr][t].bias;
            return MULTIPLIER * _type_weight * _gauge_weight / _total_weight;
        } else {
            return 0;
        }
    }

    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18.
    ///         (e.g. 1.0 == 1e18). Inflation which will be received by it is
    ///         inflation_rate * relative_weight / 1e18.
    /// @param addr Gauge address.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function gauge_relative_weight(address addr, uint256 time) external view returns (uint256) {
        return _gauge_relative_weight(addr, time);
    }

    /// @notice Get gauge weight normalized to 1e18 and also fill all the unfilled values for type and gauge records.
    /// @dev Any address can call, however nothing is recorded if the values are filled already.
    /// @param addr Gauge address.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function gauge_relative_weight_write(address addr, uint256 time) external returns (uint256) {
        _get_weight(addr);
        _get_total();  // Also calculates get_sum
        return _gauge_relative_weight(addr, time);
    }

    // TODO: Not needed?
    /// @notice Change type weight.
    /// @param weight New type weight.
    function _change_type_weight(uint256 weight) internal {
        uint256 old_weight = _get_type_weight();
        uint256 old_sum = _get_sum();
        uint256 _total_weight = _get_total();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        _total_weight = _total_weight + old_sum * weight - old_sum * old_weight;
        points_total[next_time] = _total_weight;
        points_type_weight[next_time] = weight;
        time_total = next_time;
        time_type_weight = next_time;

        emit NewTypeWeight(next_time, weight, _total_weight);
    }

    // TODO: Not needed?
    /// @notice Change gauge type weight to `weight`.
    /// @param weight New Gauge weight.
    function change_type_weight(uint256 weight) external {
        require(msg.sender == owner, "Only owner can change type weight");
        _change_type_weight(weight);
    }

    function _change_gauge_weight(address addr, uint256 weight) internal {
        // Change gauge weight
        // Only needed when testing in reality
        uint256 old_gauge_weight = _get_weight(addr);
        uint256 type_weight = _get_type_weight();
        uint256 old_sum = _get_sum();
        uint256 _total_weight = _get_total();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        points_weight[addr][next_time].bias = weight;
        time_weight[addr] = next_time;

        uint256 new_sum = old_sum + weight - old_gauge_weight;
        points_sum[next_time].bias = new_sum;
        time_sum = next_time;

        _total_weight = _total_weight + new_sum * type_weight - old_sum * type_weight;
        points_total[next_time] = _total_weight;
        time_total = next_time;

        emit NewGaugeWeight(addr, block.timestamp, weight, _total_weight);
    }

    /// @notice Change weight of gauge `addr` to `weight`.
    /// @param addr `GaugeController` contract address.
    /// @param weight New Gauge weight.
    function change_gauge_weight(address addr, uint256 weight) external {
        require(msg.sender == owner, "Only owner can change gauge weight");
        _change_gauge_weight(addr, weight);
    }

    /// @notice Allocate voting power for changing pool weights.
    /// @param _gauge_addr Gauge which `msg.sender` votes for.
    /// @param _user_weight Weight for a gauge in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0.
    function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external {
        address escrow = ve;
        PointVoting memory pv = IVEOLAS(escrow).getLastUserPoint(msg.sender);
        uint256 slope = uint256(uint128(pv.slope));
        uint256 lock_end = IVEOLAS(escrow).lockedEnd(msg.sender);
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        require(lock_end > next_time, "Your token lock expires too soon");
        require(_user_weight >= 0 && _user_weight <= 10000, "You used all your voting power");
        require(block.timestamp >= last_user_vote[msg.sender][_gauge_addr] + WEIGHT_VOTE_DELAY, "Cannot vote so often");

        // Prepare slopes and biases in memory
        // TODO: check memory vs storage
        VotedSlope memory old_slope = vote_user_slopes[msg.sender][_gauge_addr];
        uint256 old_dt;
        if (old_slope.end > next_time) {
            old_dt = old_slope.end - next_time;
        }
        uint256 old_bias = old_slope.slope * old_dt;

        // TODO: check memory vs storage
        VotedSlope memory new_slope = VotedSlope({
            slope: slope * _user_weight / 10000,
            end: lock_end,
            power: _user_weight
        });
        uint256 new_dt = lock_end - next_time; // dev: raises when expired
        uint256 new_bias = new_slope.slope * new_dt;

        uint256 power_used = vote_user_power[msg.sender];
        power_used = power_used + new_slope.power - old_slope.power;
        vote_user_power[msg.sender] = power_used;
        require(power_used >= 0 && power_used <= 10000, 'Used too much power');

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for next_time
        uint256 old_weight_bias = _get_weight(_gauge_addr);
        uint256 old_weight_slope = points_weight[_gauge_addr][next_time].slope;
        uint256 old_sum_bias = _get_sum();
        uint256 old_sum_slope = points_sum[next_time].slope;

        points_weight[_gauge_addr][next_time].bias = max(old_weight_bias + new_bias, old_bias) - old_bias;
        points_sum[next_time].bias = max(old_sum_bias + new_bias, old_bias) - old_bias;
        if (old_slope.end > next_time) {
            points_weight[_gauge_addr][next_time].slope = max(old_weight_slope + new_slope.slope, old_slope.slope) - old_slope.slope;
            points_sum[next_time].slope = max(old_sum_slope + new_slope.slope, old_slope.slope) - old_slope.slope;
        } else {
            points_weight[_gauge_addr][next_time].slope += new_slope.slope;
            points_sum[next_time].slope += new_slope.slope;
        }
        if (old_slope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changes_weight[_gauge_addr][old_slope.end] -= old_slope.slope;
            changes_sum[old_slope.end] -= old_slope.slope;
        }
        // Add slope changes for new slopes
        changes_weight[_gauge_addr][new_slope.end] += new_slope.slope;
        changes_sum[new_slope.end] += new_slope.slope;

        _get_total();

        vote_user_slopes[msg.sender][_gauge_addr] = new_slope;

        // Record last action time
        last_user_vote[msg.sender][_gauge_addr] = block.timestamp;

        emit VoteForGauge(block.timestamp, msg.sender, _gauge_addr, _user_weight);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Get current gauge weight.
    /// @param addr Gauge address.
    /// @return Gauge weight.
    function getGaugeWeight(address addr) external view returns (uint256) {
        return points_weight[addr][time_weight[addr]].bias;
    }

    // TODO: Not needed?
    /// @notice Get current type weight.
    /// @return Type weight.
    function getTypeWeight() external view returns (uint256) {
        return points_type_weight[time_type_weight];
    }

    /// @notice Get current total (type-weighted) weight.
    /// @return Total weight.
    function getTotalWeight() external view returns (uint256) {
        return points_total[time_total];
    }

    // TODO: Not needed?
    //@notice Get sum of gauge weights per type.
    //@return Sum of gauge weights.
    function getWeightsSumPerType() external view returns (uint256) {
        return points_sum[time_sum].bias;
    }
}