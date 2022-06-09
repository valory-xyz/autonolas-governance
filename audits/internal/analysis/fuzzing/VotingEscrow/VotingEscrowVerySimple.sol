// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for).
Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).
Voting escrow has time-weighted votes derived from the amount of tokens locked. The maximum voting power can be
achieved with the longest lock possible. This way the users are incentivized to lock tokens for more time.
# w ^ = amount * time_locked / MAXTIME
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime (4 years?)
*/

/// @title Voting Escrow - the workflow is ported from Curve Finance Vyper implementation
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// Code ported from: https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy
/// and: https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol

/* We cannot really do block numbers per se b/c slope is per time, not per block
* and per block could be fairly bad b/c Ethereum changes blocktimes.
* What we can do is to extrapolate ***At functions */

// Structure for voting escrow points
struct PointVoting {
	// w(i) = at + b (bias)
        int128 bias;
        // dw / dt = a (slope)
        int128 slope;
        // Timestamp
        uint256 ts;
        // Block number
        uint256 blockNumber;
        // Supply or account balance
        uint256 balance;
}


struct LockedBalance {
    int128 amount;
    uint256 end;
}

contract VotingEscrowVerySimple {
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    event Deposit(address provider, uint256 amount, uint256 locktime, DepositType depositType, uint256 ts);
    event Withdraw(address indexed provider, uint256 amount, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    // 1 week time
    uint256 internal constant WEEK = 1 weeks;
    // Maximum lock time (4 years)
    uint256 internal constant MAXTIME = 4 * 365 * 86400;

    // Token address
    address public token;
    // Total token supply
    uint256 public supply;
    // Mapping of account address => LockedBalance
    mapping(address => LockedBalance) public mapLockedBalances;

    // Total number of economical checkpoints (starting from zero)
    uint256 public totalNumPoints;
    // Mapping of point Id => point
    mapping(uint256 => PointVoting) public mapSupplyPoints;
    // Mapping of account address => PointVoting[point Id]
    mapping(address => PointVoting[]) public mapUserPoints;
    // Mapping of time => signed slope change
    mapping(uint256 => int128) public mapSlopeChanges;

    // Number of decimals
    uint8 public decimals;
    // Voting token name
    string public name;
    // Voting token symbol
    string public symbol;

    /// Echidna invariant
    bool public cond = true;

    constructor()
    {
        // simplificated for fuzzing
        mapSupplyPoints[0] = PointVoting(0, 0, block.timestamp, block.number, 0);
    }

    /// @dev Record global and per-user data to checkpoint. Target for fuzzing
    function _checkpoint(
        address account,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked,
        PointVoting memory _lastPoint,
        int128 _mapSlopeChangesOldLockedEnd,
        int128 _mapSlopeChangesNewLockedEnd,
        int128 _mapSlopeChangesTStep
    ) public {
        PointVoting memory uOld;
        PointVoting memory uNew;
        int128 oldDSlope;
        int128 newDSlope;
        // Avoid CompilerError: Stack too deep, try removing local variables.
        // uint256 curNumPoint = totalNumPoints;

        if (account != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            int128 maxTime = int128(int256(MAXTIME));
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = oldLocked.amount / maxTime;
                uOld.bias = uOld.slope * int128(int256(oldLocked.end - block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = newLocked.amount / maxTime;
                uNew.bias = uNew.slope * int128(int256(newLocked.end - block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // oldLocked.end can be in the past and in the future
            // newLocked.end can ONLY be in the FUTURE unless everything expired: than zeros
            // oldDSlope = mapSlopeChanges[oldLocked.end];
            oldDSlope = _mapSlopeChangesOldLockedEnd;
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDSlope = oldDSlope;
                } else {      
                    // newDSlope = mapSlopeChanges[newLocked.end];
                    newDSlope = _mapSlopeChangesNewLockedEnd;
                }
            }
        }

        PointVoting memory lastPoint = _lastPoint;
        // replaced for fuzzing
        uint256 lastCheckpoint = lastPoint.ts;
        // initialPoint is used for extrapolation to calculate the block number and save them
        // as we cannot figure that out in exact values from inside of the contract
        PointVoting memory initialPoint = _lastPoint;
        uint256 block_slope; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            block_slope = (1e18 * (block.number - lastPoint.blockNumber)) / (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope == 0, but we know the block already in this case
        // Go over weeks to fill in the history and (or) calculate what the current point is
        {
            uint256 tStep = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                tStep += WEEK;
                int128 dSlope;
                if (tStep > block.timestamp) {
                    tStep = block.timestamp;
                } else {
                    // dSlope = mapSlopeChanges[tStep];
                    dSlope = _mapSlopeChangesTStep;
                }
                // original code
                lastPoint.bias -= lastPoint.slope * int128(int256(tStep - lastCheckpoint));
                lastPoint.slope += dSlope;
                if (lastPoint.bias < 0) {
                    // This could potentially happen
                    // Fuzzing test1
                    // Fuzzing - echidna_test: FAILED
                    // This means that we have not reached this point in the code. cond = false;  
                    // delete comments for allow test
                    // _checkpoint(0x0,(13255173822277550, 19924632294883531292766745976815052485430145805601144699011665142736331391244),(55689825092758801341875180307371489521, 2778403),(2167087, 18, 0, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639934)) from: 0x0000000000000000000000000000000000010000
                    // _checkpoint(0x0,(14397945744268070611797456743092845514, 2),(1904371, 2973353820485614288017265722675870246219482936508317014640534871234755232404),(79896, 45, 13694, 0, 1872935072013173821166898811818983172133292685152992776700594754087834458011)) from: 0x0000000000000000000000000000000000010000
                    // _checkpoint(0x0,(1, 0),(9545329322037239075813233312954095713, 279),(1047262635, -3, 109, 238, 2839455385382566979578152780581636587905012282915053686020933385777209421981),-242846228724124618,7128578874039162075089561596583786982,1)
                    // last:
                    //1._checkpoint(0x0,(0, 2298459618750138448747256000707571851925136626997346945518223893328),
                    //(0,74982180889427631875384360535915918509098103024907565024751161),(0, 0, 0, 0, 0),148246556885407,0,1)
                    cond = false;
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // Fuzzing test2
                    // Fuzzing - echidna_test: FAILED!
                    //_checkpoint(0x0,
                    // (-201, 100353390826912211592316429676599595477699878522815124328959335377266122566142),
                    // (4, 80774372482551993083832509912901104455812792874220701830344880726560051317303),
                    // (39232, -301356726444157435, 1524785991, 2, 32166501715858826476079125252621458144948284530681561392163348819425617737644))
                    // This means that we have reached this point in the code. cond = false;
                    // delete comments for allow test
                    // cond = false;
                    lastPoint.slope = 0;
                }
                lastCheckpoint = tStep;
                lastPoint.ts = tStep;
                lastPoint.blockNumber = initialPoint.blockNumber + (block_slope * (tStep - initialPoint.ts)) / 1e18;
                // avoid in fuzzing
                // lastPoint.balance = initialPoint.balance;
                // curNumPoint += 1;
                if (tStep == block.timestamp) {
                    lastPoint.blockNumber = block.number;
                    // avoid in fuzzing
                    // lastPoint.balance = supply;
                    break;
                } else {
                    // avoid in fuzzing
                    // mapSupplyPoints[curNumPoint] = lastPoint;
                }
            }
        }

        // avoid in fuzzing
        // totalNumPoints = curNumPoint;
        {
            if (account != address(0)) {
                // If last point was in this block, the slope change has been already applied. In such case we have 0 slope(s)
                lastPoint.slope += (uNew.slope - uOld.slope);
                lastPoint.bias += (uNew.bias - uOld.bias);
                if (lastPoint.slope < 0) {
                    // Fuzzing test3
                    // delete comments for allow test
                    // cond = false;  
                    lastPoint.slope = 0;
                }
                if (lastPoint.bias < 0) {
                    // Fuzzing test4
                    // delete comments for allow test
                    // cond = false;  
                    lastPoint.bias = 0;
                }
            }
        }

        // Record the last updated point
        // avoid in fuzzing ...
    }


    /// @dev Echidna fuzzer
    function echidna_test() public returns (bool) {
        return(cond);
    }
}
