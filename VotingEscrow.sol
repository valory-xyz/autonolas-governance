// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/IStructs.sol";

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

struct LockedBalance {
    // Token amount. It will never be bigger than 2^128 - 1, since the total supply of OLA is lower
    uint128 amount;
    // Unlock time. It will never be bigger than 2^64 - 1, since we reach 2^32 - 1 in the year of 2037
    uint64 end;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract VotingEscrow is IErrors, IStructs, IVotes, IERC20, IERC165 {
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
    uint64 internal constant WEEK = 1 weeks;
    // Maximum lock time (4 years)
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    // Maximum lock time (4 years) in int128
    int128 internal constant IMAXTIME = 4 * 365 * 86400;
    // Number of decimals
    uint8 public constant decimals = 18;

    // Token address
    address immutable public token;
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
    mapping(uint64 => int128) public mapSlopeChanges;

    // Voting token name
    string public name;
    // Voting token symbol
    string public symbol;

    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
    // Reentrancy lock
    uint256 private locked = 1;

    /// @dev Contract constructor
    /// @param _token Token address.
    /// @param _name Token name.
    /// @param _symbol Token symbol.
    constructor(address _token, string memory _name, string memory _symbol)
    {
        token = _token;
        name = _name;
        symbol = _symbol;
        // Create initial point such that default timestamp and block number are not zero
        // See cast specification in the PointVoting structure
        mapSupplyPoints[0] = PointVoting(0, 0, uint64(block.timestamp), uint64(block.number), 0);
    }

    /// @dev Gets the most recently recorded user point for `account`.
    /// @param account Account address.
    /// @return pv Last checkpoint.
    function getLastUserPoint(address account) external view returns (PointVoting memory pv) {
        uint256 lastPointNumber = mapUserPoints[account].length;
        if (lastPointNumber > 0) {
            pv = mapUserPoints[account][lastPointNumber - 1];
        }
    }

    /// @dev Gets the number of user points.
    /// @param account Account address.
    /// @return accountNumPoints Number of user points.
    function getNumUserPoints(address account) external view returns (uint256 accountNumPoints) {
        accountNumPoints = mapUserPoints[account].length;
    }

    /// @dev Gets the checkpoint structure at number `idx` for `account`.
    /// @param account User wallet address.
    /// @param idx User point number.
    /// @return The requested checkpoint.
    function getUserPoint(address account, uint256 idx) external view returns (PointVoting memory) {
        return mapUserPoints[account][idx];
    }

    /// @dev Record global and per-user data to checkpoint.
    /// @param account Account address. User checkpoint is skipped if the address is zero.
    /// @param oldLocked Previous locked amount / end lock time for the user.
    /// @param newLocked New locked amount / end lock time for the user.
    /// @param curSupply Current totl supply.
    function _checkpoint(
        address account,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked,
        uint128 curSupply
    ) internal {
        PointVoting memory uOld;
        PointVoting memory uNew;
        int128 oldDSlope;
        int128 newDSlope;
        uint256 curNumPoint = totalNumPoints;

        if (account != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = int128(oldLocked.amount) / IMAXTIME;
                uOld.bias = uOld.slope * int128(oldLocked.end - uint128(block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = int128(newLocked.amount) / IMAXTIME;
                uNew.bias = uNew.slope * int128(newLocked.end - uint128(block.timestamp));
            }

            // Read values of scheduled changes in the slope
            // oldLocked.end can be in the past and in the future
            // newLocked.end can ONLY be in the FUTURE unless everything expired: than zeros
            oldDSlope = mapSlopeChanges[oldLocked.end];
            if (newLocked.end > 0) {
                if (newLocked.end == oldLocked.end) {
                    newDSlope = oldDSlope;
                } else {
                    newDSlope = mapSlopeChanges[newLocked.end];
                }
            }
        }

        PointVoting memory lastPoint;
        if (curNumPoint > 0) {
            lastPoint = mapSupplyPoints[curNumPoint];
        } else {
            // If no point is created yet, we take the actual time and block parameters
            lastPoint = PointVoting(0, 0, uint64(block.timestamp), uint64(block.number), 0);
        }
        uint64 lastCheckpoint = lastPoint.ts;
        // initialPoint is used for extrapolation to calculate the block number and save them
        // as we cannot figure that out in exact values from inside of the contract
        PointVoting memory initialPoint = lastPoint;
        uint256 block_slope; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            block_slope = (1e18 * uint256(block.number - lastPoint.blockNumber)) / uint256(block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope == 0, but we know the block already in this case
        // Go over weeks to fill in the history and (or) calculate what the current point is
        {
            // The timestamp is always rounded and > 0 and < 2**32-1 before 2037
            uint64 tStep = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; ++i) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                // This is always < 2^256-1
                unchecked {
                    tStep += WEEK;
                }
                int128 dSlope;
                if (tStep > block.timestamp) {
                    tStep = uint64(block.timestamp);
                } else {
                    dSlope = mapSlopeChanges[tStep];
                }
                lastPoint.bias -= lastPoint.slope * int128(int64(tStep - lastCheckpoint));
                lastPoint.slope += dSlope;
                if (lastPoint.bias < 0) {
                    // This could potentially happen, but fuzzer didn't find available "real" combinations
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case. Again, fuzzer didn't reach this
                    lastPoint.slope = 0;
                }
                lastCheckpoint = tStep;
                lastPoint.ts = tStep;
                lastPoint.blockNumber = initialPoint.blockNumber + uint64((block_slope * uint256(tStep - initialPoint.ts)) / 1e18);
                lastPoint.balance = initialPoint.balance;
                // In order for the overflow of total number of economical checkpoints (starting from zero)
                // the _checkpoint() call must happen n >(2**256 -1)/255 or n > ~1e77/255 > ~1e74 times
                unchecked {
                    curNumPoint += 1;    
                }
                if (tStep == block.timestamp) {
                    lastPoint.blockNumber = uint64(block.number);
                    lastPoint.balance = curSupply;
                    break;
                } else {
                    mapSupplyPoints[curNumPoint] = lastPoint;
                }
            }
        }

        totalNumPoints = curNumPoint;

        // Now mapSupplyPoints is filled until current time
        if (account != address(0)) {
            // If last point was in this block, the slope change has been already applied. In such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        // Record the last updated point
        mapSupplyPoints[curNumPoint] = lastPoint;

        if (account != address(0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [newLocked.end]
            // and add old_user_slope to [oldLocked.end]
            if (oldLocked.end > block.timestamp) {
                // oldDSlope was <something> - uOld.slope, so we cancel that
                oldDSlope += uOld.slope;
                if (newLocked.end == oldLocked.end) {
                    oldDSlope -= uNew.slope; // It was a new deposit, not extension
                }
                mapSlopeChanges[oldLocked.end] = oldDSlope;
            }

            if (newLocked.end > block.timestamp && newLocked.end > oldLocked.end) {
                newDSlope -= uNew.slope; // old slope disappeared at this point
                mapSlopeChanges[newLocked.end] = newDSlope;
                // else: we recorded it already in oldDSlope
            }
            // Now handle user history
            uNew.ts = uint64(block.timestamp);
            uNew.blockNumber = uint64(block.number);
            uNew.balance = uint128(newLocked.amount);
            mapUserPoints[account].push(uNew);
        }
    }

    /// @dev Deposits and locks tokens for a specified account.
    /// @param account Address that already holds the locked amount.
    /// @param amount Amount to deposit.
    /// @param unlockTime New time when to unlock the tokens, or 0 if unchanged.
    /// @param lockedBalance Previous locked amount / end time.
    /// @param depositType Deposit type.
    function _depositFor(
        address account,
        uint256 amount,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        DepositType depositType
    ) internal {
        uint256 supplyBefore = supply;
        uint256 supplyAfter;
        // Cannot overflow because total supply << 2^256-1
        unchecked {
            supplyAfter = supplyBefore + amount;
            supply = supplyAfter;
        }
        // Get the old locked data
        LockedBalance memory oldLocked;
        (oldLocked.amount, oldLocked.end) = (lockedBalance.amount, lockedBalance.end);
        // Adding to the existing lock, or if a lock is expired - creating a new one
        // This cannot be larger than the total supply
        unchecked {
            lockedBalance.amount += uint128(amount);
        }
        if (unlockTime > 0) {
            lockedBalance.end = uint64(unlockTime);
        }
        mapLockedBalances[account] = lockedBalance;

        // Possibilities:
        // Both oldLocked.end could be current or expired (>/< block.timestamp)
        // amount == 0 (extend lock) or amount > 0 (add to lock or extend lock)
        // lockedBalance.end > block.timestamp (always)
        _checkpoint(account, oldLocked, lockedBalance, uint128(supplyAfter));
        if (amount > 0) {
            // OLA is full standard token 
            // with correct function transfer(address to, uint256 amount) public virtual returns (bool)
            // we can avoid https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol#L29
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            if (!success) {
                revert TransferFailed(token, msg.sender, address(this), amount);
            }
        }

        emit Deposit(account, amount, lockedBalance.end, depositType, block.timestamp);
        emit Supply(supplyBefore, supplyAfter);
    }

    /// @dev Record global data to checkpoint.
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0), uint128(supply));
    }

    /// @dev Deposits `amount` tokens for `account` and adds to the lock.
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user.
    /// @param account Account address.
    /// @param amount Amount to add.
    function depositFor(address account, uint256 amount) external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;
        LockedBalance memory lockedBalance = mapLockedBalances[account];
        // Check if the amount is zero
        if (amount == 0) {
            revert ZeroValue();
        }
        // The locked balance must already exist
        if (lockedBalance.amount == 0) {
            revert NoValueLocked(account);
        }
        // Check the lock expiry
        if (lockedBalance.end < (block.timestamp + 1)) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        _depositFor(account, amount, 0, lockedBalance, DepositType.DEPOSIT_FOR_TYPE);
        locked = 1;
    }

    /// @dev Deposits `amount` tokens for `msg.sender` and lock until `unlockTime`.
    /// @param amount Amount to deposit.
    /// @param unlockTime Time when tokens unlock, rounded down to a whole week.
    function createLock(uint256 amount, uint256 unlockTime) external  {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;
        // Lock time is rounded down to weeks
        // Cannot overflow because block.timestamp + unlockTime (max 4 years) << 2^256-1
        unchecked {
            unlockTime = ((block.timestamp + unlockTime) / WEEK) * WEEK;
        }
        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        // Check if the amount is zero
        if (amount == 0) {
            revert ZeroValue();
        }
        // The locked balance must be zero in order to start the lock
        if (lockedBalance.amount > 0) {
            revert LockedValueNotZero(msg.sender, uint256(lockedBalance.amount));
        }
        // Check for the lock time correctness
        if (unlockTime < (block.timestamp + 1)) {
            revert UnlockTimeIncorrect(msg.sender, block.timestamp, unlockTime);
        }
        // Check for the lock time not to exceed the MAXTIME
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, amount, unlockTime, lockedBalance, DepositType.CREATE_LOCK_TYPE);
        locked = 1;
    }

    /// @dev Deposits `amount` additional tokens for `msg.sender` without modifying the unlock time.
    /// @param amount Amount of tokens to deposit and add to the lock.
    function increaseAmount(uint256 amount) external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;
        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        // Check if the amount is zero
        if (amount == 0) {
            revert ZeroValue();
        }
        // The locked balance must already exist
        if (lockedBalance.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        // Check the lock expiry
        if (lockedBalance.end < (block.timestamp + 1)) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }

        _depositFor(msg.sender, amount, 0, lockedBalance, DepositType.INCREASE_LOCK_AMOUNT);
        locked = 1;
    }

    /// @dev Extends the unlock time.
    /// @param unlockTime New tokens unlock time.
    function increaseUnlockTime(uint256 unlockTime) external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;
        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        // The TIMESTAMP op code costs 2 gas, according to the yellow paper
        // Cannot overflow because block.timestamp + unlockTime (max 4 years) << 2^256-1
        unchecked {
            unlockTime = ((block.timestamp + unlockTime) / WEEK) * WEEK;
        }
        // The locked balance must already exist
        if (lockedBalance.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        // Check the lock expiry
        if (lockedBalance.end < (block.timestamp + 1)) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        // Check for the lock time correctness
        if (unlockTime < (lockedBalance.end + 1)) {
            revert UnlockTimeIncorrect(msg.sender, lockedBalance.end, unlockTime);
        }
        // Check for the lock time not to exceed the MAXTIME
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, 0, unlockTime, lockedBalance, DepositType.INCREASE_UNLOCK_TIME);
        locked = 1;
    }

    /// @dev Withdraws all tokens for `msg.sender`. Only possible if the lock has expired.
    function withdraw() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;
        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        if (lockedBalance.end > block.timestamp) {
            revert LockNotExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        uint256 amount = uint256(lockedBalance.amount);

        mapLockedBalances[msg.sender] = LockedBalance(0,0);
        uint256 supplyBefore = supply;
        uint256 supplyAfter;
        // The amount cannot be less than the total supply
        unchecked {
            supplyAfter = supplyBefore - amount;
            supply = supplyAfter;
        }
        // oldLocked can have either expired <= timestamp or zero end
        // lockedBalance has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, lockedBalance, LockedBalance(0,0), uint128(supplyAfter));

        emit Withdraw(msg.sender, amount, block.timestamp);
        emit Supply(supplyBefore, supplyAfter);

        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed(token, address(this), msg.sender, amount);
        }
        locked = 1;
    }

    /// @dev Finds a closest point that has a specified block number.
    /// @param blockNumber Block to find.
    /// @param account Account address for user points.
    /// @return point Point with the approximate index number for the specified block.
    /// @return minPointNumber Point number.
    function _findPointByBlock(uint256 blockNumber, address account) internal view
        returns (PointVoting memory point, uint256 minPointNumber)
    {
        // Get the last available point number
        uint256 maxPointNumber;
        if (account == address(0)) {
            maxPointNumber = totalNumPoints;
        } else {
            maxPointNumber = mapUserPoints[account].length;
            if (maxPointNumber == 0) {
                return (point, minPointNumber);
            }
            // Already checked for > 0 in this case
            unchecked {
                maxPointNumber -= 1;
            }
        }

        // Binary search that will be always enough for 128-bit numbers
        for (uint256 i = 0; i < 128; ++i) {
            if ((minPointNumber + 1) > maxPointNumber) {
                break;
            }
            uint256 mid = (minPointNumber + maxPointNumber + 1) / 2;

            // Choose the source of points
            if (account == address(0)) {
                point = mapSupplyPoints[mid];
            } else {
                point = mapUserPoints[account][mid];
            }

            if (point.blockNumber < (blockNumber + 1)) {
                minPointNumber = mid;
            } else {
                maxPointNumber = mid - 1;
            }
        }

        // Get the found point
        if (account == address(0)) {
            point = mapSupplyPoints[minPointNumber];
        } else {
            point = mapUserPoints[account][minPointNumber];
        }
    }

    /// @dev Gets the voting power for an `account` at time `ts`.
    /// @param account Account address.
    /// @param ts Time to get voting power at.
    /// @return vBalance Account voting power.
    function _balanceOfLocked(address account, uint256 ts) internal view returns (uint256 vBalance) {
        uint256 pointNumber = mapUserPoints[account].length;
        if (pointNumber > 0) {
            PointVoting memory uPoint = mapUserPoints[account][pointNumber - 1];
            uPoint.bias -= uPoint.slope * int128(int64(uint64(ts)) - int64(uPoint.ts));
            if (uPoint.bias > 0) {
                vBalance = uint256(int256(uPoint.bias));
            }
        }
    }

    /// @dev Gets the account balance in native token.
    /// @param account Account address.
    /// @return balance Account balance.
    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = mapLockedBalances[account].amount;
    }

    /// @dev Gets the `account`'s lock end time.
    /// @param account Account address.
    /// @return unlockTime Lock end time.
    function lockedEnd(address account) external view returns (uint256 unlockTime) {
        unlockTime = mapLockedBalances[account].end;
    }

    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Account balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance) {
        // Find point with the closest block number to the provided one
        (PointVoting memory uPoint, ) = _findPointByBlock(blockNumber, account);
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        if (uPoint.blockNumber < (blockNumber + 1)) {
            balance = uPoint.balance;
        }
    }

    /// @dev Gets the voting power.
    /// @param account Account address.
    function getVotes(address account) public view override returns (uint256) {
        return _balanceOfLocked(account, block.timestamp);
    }

    /// @dev Gets the block time adjustment for two neighboring points.
    /// @param blockNumber Block number.
    /// @return point Point with the specified block number (or closest to it).
    /// @return blockTime Adjusted block time of the neighboring point.
    function _getBlockTime(uint256 blockNumber) internal view returns (PointVoting memory point, uint256 blockTime) {
        // Check the block number to be in the past or equal to the current block
        if (blockNumber > block.number) {
            revert WrongBlockNumber(blockNumber, block.number);
        }
        // Get the minimum historical point with the provided block number
        uint256 minPointNumber;
        (point, minPointNumber) = _findPointByBlock(blockNumber, address(0));

        uint256 dBlock;
        uint256 dt;
        if (minPointNumber < totalNumPoints) {
            PointVoting memory pointNext = mapSupplyPoints[minPointNumber + 1];
            dBlock = pointNext.blockNumber - point.blockNumber;
            dt = pointNext.ts - point.ts;
        } else {
            dBlock = block.number - point.blockNumber;
            dt = block.timestamp - point.ts;
        }
        blockTime = point.ts;
        if (dBlock > 0) {
            blockTime += (dt * (blockNumber - point.blockNumber)) / dBlock;
        }
    }

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256 balance) {
        // Find the user point for the provided block number
        (PointVoting memory uPoint, ) = _findPointByBlock(blockNumber, account);

        // Get block time adjustment.
        (, uint256 blockTime) = _getBlockTime(blockNumber);

        // Calculate bias based on a block time
        uPoint.bias -= uPoint.slope * int128(int64(uint64(blockTime)) - int64(uPoint.ts));
        if (uPoint.bias > 0) {
            balance = uint256(uint128(uPoint.bias));
        }
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param lastPoint The point (bias/slope) to start the search from.
    /// @param ts Time to calculate the total voting power at.
    /// @return vSupply Total voting power at that time.
    function _supplyLockedAt(PointVoting memory lastPoint, uint256 ts) internal view returns (uint256 vSupply) {
        // The timestamp is always rounded and > 0 and < 2**32-1 before 2037
        uint64 tStep = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // This is always < 2^256-1
            unchecked {
                tStep += WEEK;
            }
            int128 dSlope;
            if (tStep > ts) {
                tStep = uint64(ts);
            } else {
                dSlope = mapSlopeChanges[tStep];
            }
            lastPoint.bias -= lastPoint.slope * int128(int64(tStep) - int64(lastPoint.ts));
            if (tStep == ts) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = tStep;
        }

        if (lastPoint.bias > 0) {
            vSupply = uint256(uint128(lastPoint.bias));
        }
    }

    /// @dev Gets total token supply.
    /// @return Total token supply.
    function totalSupply() public view override returns (uint256) {
        return supply;
    }

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt) {
        // Find point with the closest block number to the provided one
        (PointVoting memory sPoint, ) = _findPointByBlock(blockNumber, address(0));
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        if (sPoint.blockNumber < (blockNumber + 1)) {
            supplyAt = sPoint.balance;
        }
    }

    /// @dev Calculates total voting power at time `ts`.
    /// @param ts Time to get total voting power at.
    /// @return Total voting power.
    function totalSupplyLockedAtT(uint256 ts) public view returns (uint256) {
        PointVoting memory lastPoint = mapSupplyPoints[totalNumPoints];
        return _supplyLockedAt(lastPoint, ts);
    }

    /// @dev Calculates current total voting power.
    /// @return Total voting power.
    function totalSupplyLocked() public view returns (uint256) {
        return totalSupplyLockedAtT(block.timestamp);
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return Total voting power.
    function getPastTotalSupply(uint256 blockNumber) public view override returns (uint256) {
        (PointVoting memory sPoint, uint256 blockTime) = _getBlockTime(blockNumber);
        // Now dt contains info on how far are we beyond the point
        return _supplyLockedAt(sPoint, blockTime);
    }

    /// @dev Gets information about the interface support.
    /// @param interfaceId A specified interface Id.
    /// @return True if this contract implements the interface defined by interfaceId.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IVotes).interfaceId;
    }

    /// @dev Bans the transfer of this token.
    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Bans the approval of this token.
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Bans the transferFrom of this token.
    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Compatibility with IERC20.
    function allowance(address owner, address spender) external view virtual override returns (uint256)
    {
        revert NonTransferable(address(this));
    }

    /// @dev Compatibility with IVotes.
    function delegates(address account) external view virtual override returns (address)
    {
        revert NonDelegatable(address(this));
    }

    /// @dev Compatibility with IVotes.
    function delegate(address delegatee) external virtual override
    {
        revert NonDelegatable(address(this));
    }

    /// @dev Compatibility with IVotes.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
    external virtual override
    {
        revert NonDelegatable(address(this));
    }
}
