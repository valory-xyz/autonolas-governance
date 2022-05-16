// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC20VotesNonTransferable.sol";
import "../interfaces/IStructs.sol";

/**
@title Voting Escrow
@author Curve Finance
@license MIT
@notice Votes have a weight depending on time, so that users are
committed to the future of (whatever they are voting for)
@dev Vote weight decays linearly over time. Lock time cannot be
more than `MAXTIME` (4 years).
# Voting escrow to have time-weighted votes
# Votes have a weight depending on time, so that users are committed
# to the future of (whatever they are voting for).
# The weight in this implementation is linear, and lock cannot be more than maxtime:
# w ^
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

//# Interface for checking whether address belongs to a whitelisted
//# type of a smart wallet.
//# When new types are added - the whole contract is changed
//# The check() method is modifying to be able to use caching
//# for individual wallet addresses
interface IChecker {
    function check(address account) external returns (bool);
}

/* We cannot really do block numbers per se b/c slope is per time, not per block
* and per block could be fairly bad b/c Ethereum changes blocktimes.
* What we can do is to extrapolate ***At functions */

struct LockedBalance {
    int128 amount;
    uint256 end;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract VotingEscrow is IStructs, Ownable, ReentrancyGuard, ERC20VotesNonTransferable {
    using SafeERC20 for IERC20;

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    event Deposit(
        address indexed provider,
        uint256 value,
        uint256 indexed locktime,
        DepositType depositType,
        uint256 ts
    );

    event Withdraw(address indexed provider, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);
    event DispenserUpdated(address dispenser);

    // 1 week time
    uint256 internal constant WEEK = 1 weeks;
    // Maximum lock time (4 years)
    uint256 internal constant MAXTIME = 4 * 365 * 86400;

    // Token address
    address immutable public token;
    // Total token supply
    uint256 public supply;
    // Mapping of account address => LockedBalance
    mapping(address => LockedBalance) public mapLockedBalance;

    // Total number of economical checkpoints (starting from zero)
    uint256 public totalNumPoints;
    // Mapping of point Id => point
    PointVoting[] public pointHistory;
    // Mapping of account address => PointVoting[point Id]
    mapping(address => PointVoting[]) public userPointHistory;
    // Mapping of time => signed slope change
    mapping(uint256 => int128) public slopeChanges;

    uint8 public decimals;
    string public name;
    string public symbol;

    // Smart wallet contract checker address for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    address public smartWalletChecker;

    /// @dev Contract constructor
    /// @param _token Token address.
    /// @param _name Token name.
    /// @param _symbol Token symbol.
    constructor(address _token, string memory _name, string memory _symbol)
    {
        token = _token;
        name = _name;
        symbol = _symbol;
        decimals = ERC20(_token).decimals();
        // Push initial point such that default timestamp and block number are not zero
        pointHistory.push(PointVoting(0, 0, block.timestamp, block.number, 0));
    }

    /// @dev Set an external contract to check for approved smart contract wallets
    /// @param checker Address of Smart contract checker
    function changeSmartWalletChecker(address checker) external onlyOwner {
        smartWalletChecker = checker;
    }

    /// @dev Check if the call is from a whitelisted smart contract, revert if not
    /// @param account Address to be checked
    function _assertNotContract(address account) internal {
        if (account != tx.origin) {
            // TODO Implement own smart contract checker or use one from oracle-dev
            if (smartWalletChecker != address(0)) {
                require(IChecker(smartWalletChecker).check(account), "SC depositors not allowed");
            }
        }
    }

    /// @dev Gets the most recently recorded user point for `account`.
    /// @param account Account address.
    /// @return pv Last checkpoint.
    function getLastUserPointHistory(address account) external view returns (PointVoting memory pv) {
        uint256 uPoint = userPointHistory[account].length;
        if (uPoint > 0) {
            pv = userPointHistory[account][uPoint - 1];
        }
    }

    /// @dev Gets the number of user points.
    /// @param account Account address.
    /// @return accountNumPoints Number of user points.
    function getNumAccountPoints(address account) external view returns (uint256 accountNumPoints) {
        accountNumPoints = userPointHistory[account].length;
    }

    /// @dev Gets the checkpoint structure at number `idx` for `account`.
    /// @param account User wallet address.
    /// @param idx User point number.
    /// @return The requested checkpoint.
    function getUserPointHistory(address account, uint256 idx) external view returns (PointVoting memory) {
        return userPointHistory[account][idx];
    }


    /// @dev Get timestamp when `account`'s lock finishes
    /// @param account User wallet
    /// @return Epoch time of the lock end
    function lockedEnd(address account) external view returns (uint256) {
        return mapLockedBalance[account].end;
    }

    /// @dev Record global and per-user data to checkpoint
    /// @param account User's wallet address. No user checkpoint if the address is zero.
    /// @param oldLocked Pevious locked amount / end lock time for the user
    /// @param newLocked New locked amount / end lock time for the user
    function _checkpoint(
        address account,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        PointVoting memory uOld;
        PointVoting memory uNew;
        int128 oldDSlope;
        int128 newDSlope;
        uint256 curNumPoint = totalNumPoints;

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
            oldDSlope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDSlope = oldDSlope;
                } else {
                    newDSlope = slopeChanges[newLocked.end];
                }
            }
        }

        PointVoting memory lastPoint;
        if (curNumPoint > 0) {
            lastPoint = pointHistory[curNumPoint];
        } else {
            lastPoint = PointVoting(0, 0, block.timestamp, block.number, supply);
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        PointVoting memory initialPoint = lastPoint;
        uint256 block_slope; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            block_slope = (1e18 * (block.number - lastPoint.blockNumber)) / (block.timestamp - lastPoint.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
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
                    dSlope = slopeChanges[tStep];
                }
                lastPoint.bias -= lastPoint.slope * int128(int256(tStep - lastCheckpoint));
                lastPoint.slope += dSlope;
                if (lastPoint.bias < 0) {
                    // This can happen
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                }
                lastCheckpoint = tStep;
                lastPoint.ts = tStep;
                lastPoint.blockNumber = initialPoint.blockNumber + (block_slope * (tStep - initialPoint.ts)) / 1e18;
                lastPoint.balance = initialPoint.balance;
                curNumPoint += 1;
                if (tStep == block.timestamp) {
                    lastPoint.blockNumber = block.number;
                    lastPoint.balance = supply;
                    break;
                } else {
                    pointHistory.push(lastPoint);
                }
            }
        }

        totalNumPoints = curNumPoint;
        // Now pointHistory is filled until t=now

        if (account != address(0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) {
                lastPoint.slope = 0;
            }
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
        }

        // Record the changed point into history
        pointHistory.push(lastPoint);

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
                slopeChanges[oldLocked.end] = oldDSlope;
            }

            if (newLocked.end > block.timestamp) {
                if (newLocked.end > oldLocked.end) {
                    newDSlope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[newLocked.end] = newDSlope;
                }
                // else: we recorded it already in oldDSlope
            }
            // Now handle user history
            uNew.ts = block.timestamp;
            uNew.blockNumber = block.number;
            uNew.balance = uint256(uint128(newLocked.amount));
            userPointHistory[account].push(uNew);
        }
    }

    /// @dev Deposit and lock tokens for a user
    /// @param account Address that holds lock
    /// @param value Amount to deposit
    /// @param unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param lockedBalance Previous locked amount / timestamp
    /// @param depositType The type of deposit
    function _depositFor(
        address account,
        uint256 value,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        DepositType depositType
    ) internal {
        uint256 supplyBefore = supply;

        supply = supplyBefore + value;
        LockedBalance memory oldLocked;
        (oldLocked.amount, oldLocked.end) = (lockedBalance.amount, lockedBalance.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        lockedBalance.amount += int128(int256(value));
        if (unlockTime != 0) {
            lockedBalance.end = unlockTime;
        }
        mapLockedBalance[account] = lockedBalance;

        // Possibilities:
        // Both oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // lockedBalance.end > block.timestamp (always)
        _checkpoint(account, oldLocked, lockedBalance);

        address from = msg.sender;
        if (value != 0) {
            IERC20(token).safeTransferFrom(from, address(this), value);
        }

        emit Deposit(account, value, lockedBalance.end, depositType, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + value);
    }

    /// @dev Record global data to checkpoint
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @dev Deposit `value` tokens for `account` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param account User's wallet address
    /// @param value Amount to add to user's lock
    function depositFor(address account, uint256 value) external nonReentrant {
        LockedBalance memory lockedBalance = mapLockedBalance[account];

        if (value == 0) {
            revert ZeroValue();
        }
        if (lockedBalance.amount == 0) {
            revert NoValueLocked(account);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        _depositFor(account, value, 0, lockedBalance, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @dev Deposit `value` tokens for `msg.sender` and lock until `_unlock_time`
    /// @param value Amount to deposit
    /// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
    function createLock(uint256 value, uint256 _unlock_time) external nonReentrant {
        _assertNotContract(msg.sender);
        uint256 unlockTime = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks
        LockedBalance memory lockedBalance = mapLockedBalance[msg.sender];

        if (value == 0) {
            revert ZeroValue();
        }
        if (lockedBalance.amount != 0) {
            revert LockedValueNotZero(msg.sender, lockedBalance.amount);
        }
        if (unlockTime <= block.timestamp) {
            revert UnlockTimeIncorrect(msg.sender, block.timestamp, unlockTime);
        }
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, value, unlockTime, lockedBalance, DepositType.CREATE_LOCK_TYPE);
    }

    /// @dev Deposit `value` additional tokens for `msg.sender` without modifying the unlock time
    /// @param value Amount of tokens to deposit and add to the lock
    function increaseAmount(uint256 value) external nonReentrant {
        _assertNotContract(msg.sender);

        LockedBalance memory lockedBalance = mapLockedBalance[msg.sender];

        if (value == 0) {
            revert ZeroValue();
        }
        if (lockedBalance.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }

        _depositFor(msg.sender, value, 0, lockedBalance, DepositType.INCREASE_LOCK_AMOUNT);
    }

    /// @dev Extend the unlock time for `msg.sender` to `_unlock_time`
    /// @param _unlock_time New number of seconds until tokens unlock
    function increaseUnlockTime(uint256 _unlock_time) external nonReentrant {
        _assertNotContract(msg.sender);

        LockedBalance memory lockedBalance = mapLockedBalance[msg.sender];
        uint256 unlockTime = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (lockedBalance.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert LockExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        if (unlockTime <= lockedBalance.end) {
            revert UnlockTimeIncorrect(msg.sender, lockedBalance.end, unlockTime);
        }
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, 0, unlockTime, lockedBalance, DepositType.INCREASE_UNLOCK_TIME);
    }

    /// @dev Withdraw all tokens for `msg.sender`
    /// @dev Only possible if the lock has expired
    function withdraw() external nonReentrant {
        LockedBalance memory lockedBalance = mapLockedBalance[msg.sender];
        if (lockedBalance.end > block.timestamp) {
            revert LockNotExpired(msg.sender, lockedBalance.end, block.timestamp);
        }
        uint256 value = uint256(int256(lockedBalance.amount));

        mapLockedBalance[msg.sender] = LockedBalance(0,0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // lockedBalance has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, lockedBalance, LockedBalance(0,0));

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supply);

        IERC20(token).safeTransfer(msg.sender, value);
    }

    function _binarySearch(PointVoting[] memory pv, uint256 maxPointNumber, uint256 blockNumber) internal view
        returns (uint256 minPointNumber)
    {
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (minPointNumber >= maxPointNumber) {
                break;
            }
            uint256 mid = (minPointNumber + maxPointNumber + 1) / 2;
            if (pv[mid].blockNumber <= blockNumber) {
                minPointNumber = mid;
            } else {
                maxPointNumber = mid - 1;
            }
        }
    }

    /// @dev Binary search to estimate point that has a block number out of all the user points.
    /// @param account Account address.
    /// @param blockNumber Block to find.
    /// @return Approximate point number for the specified block.
    function _findBlockPointIndexForAccount(address account, uint256 blockNumber) internal view returns (uint256) {
        uint256 maxPointNumber = userPointHistory[account].length;
        if (maxPointNumber > 0) {
            maxPointNumber -= 1;
        }

        return _binarySearch(userPointHistory[account], maxPointNumber, blockNumber);
    }

    /// @dev Binary search to estimate point that has a block number out of all the points.
    /// @param blockNumber Block to find.
    /// @param maxPointNumber Max point number.
    /// @return Approximate point number for the specified block.
    function _findBlockPointIndex(uint256 blockNumber, uint256 maxPointNumber) internal view returns (uint256) {
        return _binarySearch(pointHistory, maxPointNumber, blockNumber);
    }


    /// @dev Get the current voting power for `account` and time `t`
    /// @param account User wallet address
    /// @param t Epoch time to return voting power at
    /// @return vBalance User voting power.
    function _balanceOfLocked(address account, uint256 t) internal view returns (uint256 vBalance) {
        uint256 pointNumber = userPointHistory[account].length;
        if (pointNumber == 0) {
            return 0;
        } else {
            PointVoting memory uPoint = userPointHistory[account][pointNumber - 1];
            uPoint.bias -= uPoint.slope * int128(int256(t) - int256(uPoint.ts));
            if (uPoint.bias > 0) {
                vBalance = uint256(int256(uPoint.bias));
            }
        }
    }

    /// @dev Gets the account balance.
    /// @param account Account address.
    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = uint256(int256(mapLockedBalance[account].amount));
    }

    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Token balance.
    /// @return pointIdx Index of a point with the requested block number balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance, uint256 pointIdx) {
        // Find point with the closest block number to the provided one
        pointIdx = _findBlockPointIndexForAccount(account, blockNumber);
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        PointVoting memory uPoint = userPointHistory[account][pointIdx];
        if (uPoint.blockNumber <= blockNumber) {
            balance = uPoint.balance;
        }
    }

    /// @dev Gets the voting power.
    /// @param account Account address.
    function getVotes(address account) public view override returns (uint256) {
        return _balanceOfLocked(account, block.timestamp);
    }

    function _getBlockTime(uint256 blockNumber) internal view returns (PointVoting memory hPoint, uint256 blockTime) {
        // Check the block number to be in the past or current block
        if (blockNumber > block.number) {
            revert WrongBlockNumber(blockNumber, block.number);
        }
        // Get the minimum historical point with the provided block number
        uint256 maxPoint = totalNumPoints;
        uint256 hMin = _findBlockPointIndex(blockNumber, maxPoint);
        hPoint = pointHistory[hMin];

        uint256 dBlock;
        uint256 dt;
        if (hMin < maxPoint) {
            PointVoting memory hPointNext = pointHistory[hMin + 1];
            dBlock = hPointNext.blockNumber - hPoint.blockNumber;
            dt = hPointNext.ts - hPoint.ts;
        } else {
            dBlock = block.number - hPoint.blockNumber;
            dt = block.timestamp - hPoint.ts;
        }
        blockTime = hPoint.ts;
        if (dBlock > 0) {
            blockTime += (dt * (blockNumber - hPoint.blockNumber)) / dBlock;
        }
    }

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256 balance) {
        (, uint256 blockTime) = _getBlockTime(blockNumber);

        // Find the user point for the provided block number
        uint256 uMin = _findBlockPointIndexForAccount(account, blockNumber);
        PointVoting memory uPoint = userPointHistory[account][uMin];
        // Calculate bias based on a block time
        uPoint.bias -= uPoint.slope * int128(int256(blockTime - uPoint.ts));
        if (uPoint.bias > 0) {
            balance = uint256(uint128(uPoint.bias));
        }
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param lastPoint The point (bias/slope) to start search from.
    /// @param t Time to calculate the total voting power at.
    /// @return vSupply Total voting power at that time.
    function _supplyLockedAt(PointVoting memory lastPoint, uint256 t) internal view returns (uint256 vSupply) {
        uint256 tStep = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            tStep += WEEK;
            int128 dSlope;
            if (tStep > t) {
                tStep = t;
            } else {
                dSlope = slopeChanges[tStep];
            }
            lastPoint.bias -= lastPoint.slope * int128(int256(tStep - lastPoint.ts));
            if (tStep == t) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = tStep;
        }

        if (lastPoint.bias > 0) {
            vSupply = uint256(uint128(lastPoint.bias));
        }
    }

    /// @dev Calculate total voting power at time `t`. Adheres to the ERC20 `totalSupplyLocked` for Aragon compatibility
    /// @return Total voting power
    function totalSupplyLockedAtT(uint256 t) public view returns (uint256) {
        PointVoting memory lastPoint = pointHistory[totalNumPoints];
        return _supplyLockedAt(lastPoint, t);
    }

    /// @dev Gets total token supply.
    /// @return Total token supply.
    function totalSupply() public view override returns (uint256) {
        return supply;
    }

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    /// @return pointIdx Index of a point with the requested block number balance.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt, uint256 pointIdx) {
        // Find point with the closest block number to the provided one
        pointIdx = _findBlockPointIndex(blockNumber, totalNumPoints);
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        PointVoting memory pv = pointHistory[pointIdx];
        if (pv.blockNumber <= blockNumber) {
            supplyAt = pv.balance;
        }
    }
    
    /// @dev Calculate total voting power
    /// @return Total voting power
    function totalSupplyLocked() public view returns (uint256) {
        return totalSupplyLockedAtT(block.timestamp);
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return Total voting power.
    function getPastTotalSupply(uint256 blockNumber) public view override returns (uint256) {
        (PointVoting memory hPoint, uint256 blockTime) = _getBlockTime(blockNumber);

        // Now dt contains info on how far are we beyond the point
        return _supplyLockedAt(hPoint, blockTime);
    }
}
