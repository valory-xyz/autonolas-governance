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
    event NewGaugeWeight(address indexed gauge_address, uint256 weight, uint256 total_weight);
    event VoteForGauge(address indexed user, address indexed gauge_addr, uint256 weight);
    event NewGauge(address addr, uint256 weight);

    // 7 * 86400 seconds - all future times are rounded by week
    uint256 public constant WEEK = 604800;
    // Cannot change weight votes more often than once in 10 days
    uint256 public constant WEIGHT_VOTE_DELAY = 864000;
    // veOLAS contract address
    address public immutable ve;
    // Contract owner address
    address public owner;

    // TODO: Convert both to cyclic map
    // Set of gauges
    address[] public gauges;
    // mapping of gauges
    mapping(address => bool) public mapGauges;

    // user -> gauge_addr -> VotedSlope
    mapping(address => mapping(address => VotedSlope)) public vote_user_slopes;
    // Total vote power used by user
    mapping(address => uint256) public vote_user_power;
    // Last user vote's timestamp for each gauge address
    mapping(address => mapping(address => uint256)) public last_user_vote;

    // Past and scheduled points for gauge weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    // gauge_addr -> time -> Point
    mapping(address => mapping(uint256 => Point)) public points_weight;
    // gauge_addr -> time -> slope
    mapping(address => mapping(uint256 => uint256)) public changes_weight;
    // gauge_addr -> last scheduled time (next week)
    mapping(address => uint256) public time_weight;

    // time -> Point
    mapping(uint256 => Point) public points_sum;
    // time -> slope
    mapping(uint256 => uint256) public changes_sum;
    // last scheduled time (next week)
    uint256 public time_sum;

    /// @notice Contract constructor.
    /// @param _ve `VotingEscrow` contract address.
    constructor(address _ve) {
        // Check for the zero address
        if (_ve != address(0)) {
            revert ZeroAddress();
        }

        // Set initial parameters
        owner = msg.sender;
        ve = _ve;
        time_sum = block.timestamp / WEEK * WEEK;
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

    /// @notice Fill sum of gauge weights for the same type week-over-week for missed checkins and return the sum for the future week.
    /// @return Sum of weights.
    function _getSum() internal returns (uint256) {
        uint256 t = time_sum;
        if (t > 0) {
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

    /// @notice Fill historic gauge weights week-over-week for missed checkins and return the total for the future week.
    /// @param gauge_addr Address of the gauge.
    /// @return Gauge weight.
    function _getWeight(address gauge_addr) internal returns (uint256) {
        // Check that the gauge exists
        if (!mapGauges[gauge_addr]) {
            revert("Does not exist");
        }

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
        if (mapGauges[addr]) {
            revert("Cannot add the same gauge twice");
        }
        mapGauges[addr] = true;

        gauges.push(addr);

        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        if (weight > 0) {
            uint256 _old_sum = _getSum();

            points_sum[next_time].bias = weight + _old_sum;
            time_sum = next_time;

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
        _getSum();
    }

    /// @notice Checkpoint to fill data for both a specific gauge and common for all gauges.
    /// @param addr Gauge address.
    function checkpoint_gauge(address addr) external {
        _getWeight(addr);
        _getSum();
    }

    /// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18 (e.g. 1.0 == 1e18).
    ///         Inflation which will be received by it is inflation_rate * relative_weight / 1e18.
    /// @param addr Gauge address.
    /// @param time Relative weight at the specified timestamp in the past or present.
    /// @return Value of relative weight normalized to 1e18.
    function _gauge_relative_weight(address addr, uint256 time) internal view returns (uint256) {
        uint256 t = time / WEEK * WEEK;
        uint256 _total_sum = points_sum[t].bias;

        if (_total_sum > 0) {
            uint256 _gauge_weight = points_weight[addr][t].bias;
            return 1e18 * _gauge_weight / _total_sum;
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
        _getWeight(addr);
        _getSum();
        return _gauge_relative_weight(addr, time);
    }

    /// @notice Get gauge weight normalized to 1e18 and also fill all the unfilled values for type and gauge records.
    /// @dev Any address can call, however nothing is recorded if the values are filled already.
    /// @param addr Gauge address.
    /// @return Value of relative weight normalized to 1e18.
    function gauge_relative_weight_write_now(address addr) external returns (uint256) {
        _getWeight(addr);
        _getSum();
        return _gauge_relative_weight(addr, block.timestamp);
    }

    function _change_gauge_weight(address addr, uint256 weight) internal {
        // Change gauge weight
        // Only needed when testing in reality
        uint256 old_gauge_weight = _getWeight(addr);
        uint256 old_sum = _getSum();
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        points_weight[addr][next_time].bias = weight;
        time_weight[addr] = next_time;

        uint256 new_sum = old_sum + weight - old_gauge_weight;
        points_sum[next_time].bias = new_sum;
        time_sum = next_time;

        emit NewGaugeWeight(addr, weight, new_sum);
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
        PointVoting memory pv = IVEOLAS(ve).getLastUserPoint(msg.sender);
        uint256 slope = uint256(uint128(pv.slope));
        uint256 lock_end = IVEOLAS(ve).lockedEnd(msg.sender);
        uint256 next_time = (block.timestamp + WEEK) / WEEK * WEEK;

        require(lock_end > next_time, "Your token lock expires too soon");
        require(_user_weight >= 0 && _user_weight <= 10000, "You used all your voting power");
        require(block.timestamp >= last_user_vote[msg.sender][_gauge_addr] + WEIGHT_VOTE_DELAY, "Cannot vote so often");

        // Prepare old and new slopes and biases
        VotedSlope memory old_slope = vote_user_slopes[msg.sender][_gauge_addr];
        uint256 old_bias;
        if (old_slope.end > next_time) {
            old_bias = old_slope.slope * (old_slope.end - next_time);
        }

        VotedSlope memory new_slope = VotedSlope({
            slope: slope * _user_weight / 10000,
            end: lock_end,
            power: _user_weight
        });

        // Check for the lock end expiration
        if (next_time > lock_end) {
            revert LockExpired(msg.sender, lock_end, next_time);
        }
        uint256 new_bias = new_slope.slope * (lock_end - next_time);

        uint256 power_used = vote_user_power[msg.sender];
        power_used = power_used + new_slope.power - old_slope.power;
        vote_user_power[msg.sender] = power_used;
        require(power_used >= 0 && power_used <= 10000, 'Used too much power');

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for next_time
        points_weight[_gauge_addr][next_time].bias = _maxAndSub(_getWeight(_gauge_addr) + new_bias, old_bias);
        points_sum[next_time].bias = _maxAndSub(_getSum() + new_bias, old_bias);
        if (old_slope.end > next_time) {
            points_weight[_gauge_addr][next_time].slope = _maxAndSub(points_weight[_gauge_addr][next_time].slope + new_slope.slope, old_slope.slope);
            points_sum[next_time].slope = _maxAndSub(points_sum[next_time].slope + new_slope.slope, old_slope.slope);
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

        vote_user_slopes[msg.sender][_gauge_addr] = new_slope;

        // Record last action time
        last_user_vote[msg.sender][_gauge_addr] = block.timestamp;

        emit VoteForGauge(msg.sender, _gauge_addr, _user_weight);
    }

    function _maxAndSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /// @notice Get current gauge weight.
    /// @param addr Gauge address.
    /// @return Gauge weight.
    function getGaugeWeight(address addr) external view returns (uint256) {
        return points_weight[addr][time_weight[addr]].bias;
    }
    
    //@notice Get sum of gauge weights.
    //@return Sum of gauge weights.
    function getWeightsSum() external view returns (uint256) {
        return points_sum[time_sum].bias;
    }

    /// @notice Gets Gauge relative weight normalized to 1e18 at the last available timestamp.
    /// @param addr Gauge address.
    /// @return Value of relative weight normalized to 1e18.
    function gauge_relative_weight_last(address addr) external view returns (uint256) {
        return _gauge_relative_weight(addr, time_sum);
    }

    /// @notice Gets Gauge relative weight normalized to 1e18 at the block timestamp.
    /// @param addr Gauge address.
    /// @return Value of relative weight normalized to 1e18.
    function gauge_relative_weight_now(address addr) external view returns (uint256) {
        return _gauge_relative_weight(addr, block.timestamp);
    }
}