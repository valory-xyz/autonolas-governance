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
import "hardhat/console.sol";

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

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    int128 internal constant iMAXTIME = 4 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;

    // Token address
    address immutable public token;
    // Dispenser address
    address public dispenser;
    // Total token supply
    uint256 public supply;
    // Mapping of account address => LockedBalance
    mapping(address => LockedBalance) public locked;

    uint256 public epoch;
    // Mapping of epoch Id => point
    mapping(uint256 => PointVoting) public pointHistory;
    // Mapping of account address => PointVoting[epoch Id]
    mapping(address => PointVoting[]) public userPointHistory;
    // Mapping of time => signed slope change
    mapping(uint256 => int128) public slopeChanges;
    // Map of block number => total supply
    mapping(uint256 => uint256) public mapBlockNumberSupply;

    // Aragon's view methods for compatibility
    address public controller;
    bool public transfersEnabled;

    uint8 public decimals;
    string public name;
    string public symbol;
    string public version;

    // Smart wallet contract checker address for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    address public smartWalletChecker;

    /// @dev Contract constructor
    /// @param tokenAddr token address
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _version Contract version - required for Aragon compatibility
    constructor(address tokenAddr, string memory _name, string memory _symbol, string memory _version, address _dispenser)
    {
        token = tokenAddr;
        pointHistory[0].blockNumber = block.number;
        pointHistory[0].ts = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;
        name = _name;
        symbol = _symbol;
        version = _version;
        decimals = ERC20(tokenAddr).decimals();
        if (decimals > 255) {
            revert Overflow(uint256(decimals), 255);
        }
        dispenser = _dispenser;
    }

    /// @dev Changes dispenser address.
    /// @param newDispenser Address of a new dispenser.
    function changeDispenser(address newDispenser) external onlyOwner {
        dispenser = newDispenser;
        emit DispenserUpdated(newDispenser);
    }

    /// @dev Set an external contract to check for approved smart contract wallets
    /// @param checker Address of Smart contract checker
    function changeSmartWalletChecker(address checker) external onlyOwner {
        smartWalletChecker = checker;
    }

    /// @dev Check if the call is from a whitelisted smart contract, revert if not
    /// @param account Address to be checked
    function assertNotContract(address account) internal {
        if (account != tx.origin) {
            // TODO Implement own smart contract checker or use one from oracle-dev
            if (smartWalletChecker != address(0)) {
                require(IChecker(smartWalletChecker).check(account), "SC depositors not allowed");
            }
        }
    }

    /// @dev Get the most recently recorded rate of voting power decrease for `account`
    /// @param account Address of the user wallet
    /// @return Value of the slope
    function getLastUserSlope(address account) external view returns (int128) {
        uint256 uepoch = userPointHistory[account].length;
        if (uepoch == 0) {
            return 0;
        }
        return userPointHistory[account][uepoch - 1].slope;
    }


    /// @dev Get the timestamp for checkpoint `_idx` for `_addr`
    /// @param _addr User wallet address
    /// @param _idx User epoch number
    /// @return Epoch time of the checkpoint
    function userPointHistoryTs(address _addr, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_addr][_idx].ts;
    }


    /// @dev Get timestamp when `_addr`'s lock finishes
    /// @param _addr User wallet
    /// @return Epoch time of the lock end
    function lockedEnd(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    /// @dev Record global and per-user data to checkpoint
    /// @param account User's wallet address. No user checkpoint if 0x0
    /// @param oldLocked Pevious locked amount / end lock time for the user
    /// @param newLocked New locked amount / end lock time for the user
    function _checkpoint(
        address account,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        PointVoting memory uOld;
        PointVoting memory uNew;
        int128 oldDSlope = 0;
        int128 newDSlope = 0;
        uint256 _epoch = epoch;

        if (account != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = oldLocked.amount / iMAXTIME;
                uOld.bias = uOld.slope * int128(int256(oldLocked.end - block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = newLocked.amount / iMAXTIME;
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
        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
        } else {
            lastPoint = PointVoting({bias: 0, slope: 0, ts: block.timestamp, blockNumber: block.number, balance: supply});
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        PointVoting memory initialLastPoint = lastPoint;
        uint256 block_slope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            block_slope = (MULTIPLIER * (block.number - lastPoint.blockNumber)) / (block.timestamp - lastPoint.ts);
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
                int128 dSlope = 0;
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
                lastPoint.blockNumber = initialLastPoint.blockNumber + (block_slope * (tStep - initialLastPoint.ts)) / MULTIPLIER;
                lastPoint.balance = initialLastPoint.balance;
                _epoch += 1;
                if (tStep == block.timestamp) {
                    lastPoint.blockNumber = block.number;
                    lastPoint.balance = supply;
                    break;
                } else {
                    pointHistory[_epoch] = lastPoint;
                }
            }
        }

        epoch = _epoch;
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
        pointHistory[_epoch] = lastPoint;

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
    /// @param _addr Address that holds lock
    /// @param _value Amount to deposit
    /// @param unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param lockedBalance Previous locked amount / timestamp
    /// @param depositType The type of deposit
    function _depositFor(
        address _addr,
        uint256 _value,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        DepositType depositType
    ) internal {
        LockedBalance memory _locked = lockedBalance;
        uint256 supplyBefore = supply;

        supply = supplyBefore + _value;
        LockedBalance memory oldLocked;
        (oldLocked.amount, oldLocked.end) = (_locked.amount, _locked.end);
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += int128(int256(_value));
        if (unlockTime != 0) {
            _locked.end = unlockTime;
        }
        locked[_addr] = _locked;

        // Possibilities:
        // Both oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_addr, oldLocked, _locked);

        address from = msg.sender;
        if (_value != 0) {
            IERC20(token).safeTransferFrom(from, address(this), _value);
        }

        emit Deposit(_addr, _value, _locked.end, depositType, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    /// @dev Record global data to checkpoint
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @dev Deposit `_value` tokens for `_addr` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _addr User's wallet address
    /// @param _value Amount to add to user's lock
    function depositFor(address _addr, uint256 _value) external nonReentrant {
        LockedBalance memory _locked = locked[_addr];

        if (_value == 0) {
            revert ZeroValue();
        }
        if (_locked.amount == 0) {
            revert NoValueLocked(_addr);
        }
        if (_locked.end <= block.timestamp) {
            revert LockExpired(msg.sender, _locked.end, block.timestamp);
        }
        _depositFor(_addr, _value, 0, _locked, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @dev Deposit `_value` tokens for `msg.sender` and lock until `_unlock_time`
    /// @param _value Amount to deposit
    /// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
    function createLock(uint256 _value, uint256 _unlock_time) external nonReentrant {
        assertNotContract(msg.sender);
        uint256 unlockTime = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks
        LockedBalance memory _locked = locked[msg.sender];

        if (_value == 0) {
            revert ZeroValue();
        }
        if (_locked.amount != 0) {
            revert LockedValueNotZero(msg.sender, _locked.amount);
        }
        if (unlockTime <= block.timestamp) {
            revert UnlockTimeIncorrect(msg.sender, block.timestamp, unlockTime);
        }
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, _value, unlockTime, _locked, DepositType.CREATE_LOCK_TYPE);
    }

    /// @dev Deposit `_value` additional tokens for `msg.sender` without modifying the unlock time
    /// @param _value Amount of tokens to deposit and add to the lock
    function increaseAmount(uint256 _value) external nonReentrant {
        assertNotContract(msg.sender);

        LockedBalance memory _locked = locked[msg.sender];

        if (_value == 0) {
            revert ZeroValue();
        }
        if (_locked.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        if (_locked.end <= block.timestamp) {
            revert LockExpired(msg.sender, _locked.end, block.timestamp);
        }

        _depositFor(msg.sender, _value, 0, _locked, DepositType.INCREASE_LOCK_AMOUNT);
    }

    /// @dev Extend the unlock time for `msg.sender` to `_unlock_time`
    /// @param _unlock_time New number of seconds until tokens unlock
    function increaseUnlockTime(uint256 _unlock_time) external nonReentrant {
        assertNotContract(msg.sender);

        LockedBalance memory _locked = locked[msg.sender];
        uint256 unlockTime = (_unlock_time / WEEK) * WEEK; // Locktime is rounded down to weeks

        if (_locked.amount == 0) {
            revert NoValueLocked(msg.sender);
        }
        if (_locked.end <= block.timestamp) {
            revert LockExpired(msg.sender, _locked.end, block.timestamp);
        }
        if (unlockTime <= _locked.end) {
            revert UnlockTimeIncorrect(msg.sender, _locked.end, unlockTime);
        }
        if (unlockTime > block.timestamp + MAXTIME) {
            revert MaxUnlockTimeReached(msg.sender, block.timestamp + MAXTIME, unlockTime);
        }

        _depositFor(msg.sender, 0, unlockTime, _locked, DepositType.INCREASE_UNLOCK_TIME);
    }

    /// @dev Withdraw all tokens for `msg.sender`
    /// @dev Only possible if the lock has expired
    function withdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];
        if (_locked.end > block.timestamp) {
            revert LockNotExpired(msg.sender, _locked.end, block.timestamp);
        }
        uint256 value = uint256(int256(_locked.amount));

        locked[msg.sender] = LockedBalance(0,0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, _locked, LockedBalance(0,0));

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supply);

        IERC20(token).safeTransfer(msg.sender, value);
    }

    /// @dev Binary search to estimate point that has a block number out of all the user points.
    /// @param account Account address.
    /// @param blockNumber Block to find.
    /// @return Approximate point number for the specified block.
    function _findBlockPointIndexForAccount(address account, uint256 blockNumber) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = userPointHistory[account].length;
        if (_max > 0) {
            _max -= 1;
        }

        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[account][_mid].blockNumber <= blockNumber) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    // TODO Refactor with the function above to make a single binary search function.
    /// @dev Binary search to estimate point that has a block number out of all the points.
    /// @param blockNumber Block to find.
    /// @param maxPointNumber Max point number.
    /// @return Approximate point number for the specified block.
    function _findBlockPointIndex(uint256 blockNumber, uint256 maxPointNumber) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = maxPointNumber;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blockNumber <= blockNumber) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }


    /// @dev Get the current voting power for `account` and time `t`
    /// @param account User wallet address
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _balanceOfLocked(address account, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = userPointHistory[account].length;
        if (_epoch == 0) {
            return 0;
        } else {
            PointVoting memory lastPoint = userPointHistory[account][_epoch - 1];
            lastPoint.bias -= lastPoint.slope * int128(int256(_t) - int256(lastPoint.ts));
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint256(int256(lastPoint.bias));
        }
    }

    /// @dev Gets the account balance.
    /// @param account Account address.
    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = uint256(int256(locked[account].amount));
    }

    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Token balance.
    /// @return pointIdx Index of a point with the requested block number balance.
    function balanceOfAt(address account, uint256 blockNumber) public view returns (uint256 balance, uint256 pointIdx) {
        // Find point with the closest block number to the provided one
        pointIdx = _findBlockPointIndexForAccount(account, blockNumber);
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        if (userPointHistory[account][pointIdx].blockNumber > blockNumber) {
            balance = 0;
        } else {
            balance = userPointHistory[account][pointIdx].balance;
        }
    }

    /// @dev Gets the account block number by the provided point number.
    /// @param account Account address.
    /// @param pointNumber Point number.
    /// @return blockNumber Block number at that point.
    function getBlockNumberByPoint(address account, uint256 pointNumber) external view returns (uint256 blockNumber) {
        if (pointNumber >= userPointHistory[account].length) {
            revert Overflow(pointNumber, userPointHistory[account].length);
        }
        blockNumber = userPointHistory[account][pointNumber].blockNumber;
    }

    /// @dev Gets historical points of an account.
    /// @param account Account address.
    /// @param startBlock Starting block.
    /// @param endBlock Ending block.
    /// @return numBlockCheckpoints Number of distinct block numbers where balances change.
    /// @return blocks Set of block numbers where balances change.
    /// @return balances Set of balances correspondent to set of block numbers.
    function getHistoryAccountBalances(address account, uint256 startBlock, uint256 endBlock) external view
        returns (uint256 numBlockCheckpoints, uint256[] memory blocks, uint256[] memory balances)
    {
        // Get all the user history points
        PointVoting[] memory points = userPointHistory[account];
        uint256 maxNumPoints = points.length;
        // Check if account has any records of locking
        if (maxNumPoints == 0) {
            revert ZeroValue();
        }

        // If it's the very first record, it has to be taken as a block number of a first point record
        if (startBlock == 0) {
            startBlock = points[0].blockNumber;
        }
        // Check provided boundaries
        if (startBlock > endBlock) {
            revert Overflow(startBlock, endBlock);
        }
        // Check for the last existent block number
        if (endBlock > block.number) {
            revert WrongBlockNumber(endBlock, block.number);
        }

        console.log("startBlock", startBlock);
        console.log("endBlock", endBlock);
        for (uint256 i = 0; i < maxNumPoints; ++i) {
            console.log("i", i);
            console.log("block", points[i].blockNumber);
        }

        uint256 lastBlockNumber = startBlock;
        // Find the point number that has a block number equal to a lower block number bound or lower
        (uint256 lastBalance, uint256 startPointIdx) = balanceOfAt(account, startBlock);
        console.log("startPointIdx", startPointIdx);
        console.log("maxNumPoints", maxNumPoints);

        // Check the points limit
        if (maxNumPoints < startPointIdx) {
            revert Overflow(startPointIdx, maxNumPoints);
        }
        // The number of block checkpoints cannot be more than the number of points we have to traverse
        maxNumPoints = maxNumPoints - startPointIdx;
        uint256[] memory allBlocks = new uint256[](maxNumPoints);
        uint256[] memory allBalances = new uint256[](maxNumPoints);

        // Record zero index balance and block number
        allBlocks[0] = lastBlockNumber;
        allBalances[0] = lastBalance;
        // Traverse all possible points until we pass the ending block number
        for (uint256 i = startPointIdx + 1; i < maxNumPoints; ++i) {
            if (points[i].blockNumber > endBlock) {
                break;
            }
            uint256 balance = points[i].balance;
            uint256 blockNumber = points[i].blockNumber;
            if (balance != lastBalance) {
                // If block number has changed, we add that block number to the set of block number checkpoints
                if (blockNumber > lastBlockNumber) {
                    numBlockCheckpoints++;
                    allBlocks[numBlockCheckpoints] = blockNumber;
                }
                // The balance is overwritten anyway since we need to know the last balance at the end of the block
                allBalances[numBlockCheckpoints] = balance;
                lastBalance = balance;
                lastBlockNumber = blockNumber;
            }
        }
        // Correct the counter to become length
        numBlockCheckpoints++;

        // Write exact number of values into the returned sets
        blocks = new uint256[](numBlockCheckpoints);
        balances = new uint256[](numBlockCheckpoints);
        for (uint256 i = 0; i < numBlockCheckpoints; ++i) {
            blocks[i] = allBlocks[i];
            balances[i] = allBalances[i];
        }
    }

    // TODO Refactor with the function above to make a single function. Now they only differe in binary search call
    /// @dev Gets historical total supply values.
    /// @param startBlock Starting block.
    /// @param endBlock Ending block.
    /// @return numBlockCheckpoints Number of distinct block numbers where balances change.
    /// @return blocks Set of block numbers where balances change.
    /// @return balances Set of balances correspondent to set of block numbers.
    function getHistoryTotalSupply(uint256 startBlock, uint256 endBlock) external view
        returns (uint256 numBlockCheckpoints, uint256[] memory blocks, uint256[] memory balances)
    {
        // Get all the general history points
        uint256 maxNumPoints = epoch;
        // Check if account has any records of locking
        if (maxNumPoints == 0) {
            revert ZeroValue();
        }

        // If it's the very first record, it has to be taken as a block number of a first point record
        if (startBlock == 0) {
            startBlock = pointHistory[0].blockNumber;
        }
        // Check provided boundaries
        if (startBlock > endBlock) {
            revert Overflow(startBlock, endBlock);
        }
        // Check for the last existent block number
        if (endBlock > block.number) {
            revert WrongBlockNumber(endBlock, block.number);
        }

        // Find the point number that has a block number equal to a lower block number bound or lower
        (uint256 lastBalance, uint256 startPointIdx) = totalSupplyAt(startBlock);
        uint256 lastBlockNumber = startBlock;

        // Check the points limit
        if (maxNumPoints < startPointIdx) {
            revert Overflow(startPointIdx, maxNumPoints);
        }
        // The number of block checkpoints cannot be more than the number of points we have to traverse
        maxNumPoints = maxNumPoints - startPointIdx;
        uint256[] memory allBlocks = new uint256[](maxNumPoints);
        uint256[] memory allBalances = new uint256[](maxNumPoints);

        // Record zero index balance and block number
        allBlocks[0] = lastBlockNumber;
        allBalances[0] = lastBalance;
        // Traverse all possible points until we pass the ending block number
        for (uint256 i = startPointIdx + 1; i < maxNumPoints; ++i) {
            if (pointHistory[i].blockNumber > endBlock) {
                break;
            }
            uint256 balance = pointHistory[i].balance;
            uint256 blockNumber = pointHistory[i].blockNumber;
            if (balance != lastBalance) {
                // If block number has changed, we add that block number to the set of block number checkpoints
                if (blockNumber > lastBlockNumber) {
                    numBlockCheckpoints++;
                    allBlocks[numBlockCheckpoints] = blockNumber;
                }
                // The balance is overwritten anyway since we need to know the last balance at the end of the block
                allBalances[numBlockCheckpoints] = balance;
                lastBalance = balance;
                lastBlockNumber = blockNumber;
            }
        }
        numBlockCheckpoints++;

        // Write exact number of values into the returned sets
        blocks = new uint256[](numBlockCheckpoints);
        balances = new uint256[](numBlockCheckpoints);
        for (uint256 i = 0; i < numBlockCheckpoints; ++i) {
            blocks[i] = allBlocks[i];
            balances[i] = allBalances[i];
        }
    }

    /// @dev Gets the voting power.
    /// @param account Account address.
    function getVotes(address account) public view override returns (uint256) {
        return _balanceOfLocked(account, block.timestamp);
    }

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        if (blockNumber > block.number) {
            revert WrongBlockNumber(blockNumber, block.number);
        }

        // Binary search
        uint256 _min = _findBlockPointIndexForAccount(account, blockNumber);

        PointVoting memory uPoint = userPointHistory[account][_min];

        uint256 maxEpoch = epoch;
        uint256 _epoch = _findBlockPointIndex(blockNumber, maxEpoch);
        PointVoting memory point0 = pointHistory[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;
        if (_epoch < maxEpoch) {
            PointVoting memory point1 = pointHistory[_epoch + 1];
            d_block = point1.blockNumber - point0.blockNumber;
            d_t = point1.ts - point0.ts;
        } else {
            d_block = block.number - point0.blockNumber;
            d_t = block.timestamp - point0.ts;
        }
        uint256 block_time = point0.ts;
        if (d_block != 0) {
            block_time += (d_t * (blockNumber - point0.blockNumber)) / d_block;
        }

        uPoint.bias -= uPoint.slope * int128(int256(block_time - uPoint.ts));
        if (uPoint.bias >= 0) {
            return uint256(uint128(uPoint.bias));
        } else {
            return 0;
        }
    }

    /// @dev Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param t Time to calculate the total voting power at
    /// @return Total voting power at that time
    function supplyLockedAt(PointVoting memory point, uint256 t) internal view returns (uint256) {
        PointVoting memory lastPoint = point;
        uint256 tStep = (lastPoint.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            tStep += WEEK;
            int128 dSlope = 0;
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

        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(uint128(lastPoint.bias));
    }

    /// @dev Calculate total voting power at time `t`. Adheres to the ERC20 `totalSupplyLocked` for Aragon compatibility
    /// @return Total voting power
    function totalSupplyLockedAtT(uint256 t) public view returns (uint256) {
        uint256 _epoch = epoch;
        PointVoting memory lastPoint = pointHistory[_epoch];
        return supplyLockedAt(lastPoint, t);
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
    function totalSupplyAt(uint256 blockNumber) public view returns (uint256 supplyAt, uint256 pointIdx) {
        // Find point with the closest block number to the provided one
        pointIdx = _findBlockPointIndex(blockNumber, epoch);
        // If the block number at the point index is bigger than the specified block number, the balance was zero
        if (pointHistory[pointIdx].blockNumber > blockNumber) {
            supplyAt = 0;
        } else {
            supplyAt = pointHistory[pointIdx].balance;
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
        if (blockNumber > block.number) {
            revert WrongBlockNumber(blockNumber, block.number);
        }
        uint256 _epoch = epoch;
        uint256 target_epoch = _findBlockPointIndex(blockNumber, _epoch);

        PointVoting memory point = pointHistory[target_epoch];
        uint256 dt = 0;
        if (target_epoch < _epoch) {
            PointVoting memory pointNext = pointHistory[target_epoch + 1];
            if (point.blockNumber != pointNext.blockNumber) {
                dt = ((blockNumber - point.blockNumber) * (pointNext.ts - point.ts)) / (pointNext.blockNumber - point.blockNumber);
            }
        } else {
            if (point.blockNumber != block.number) {
                dt = ((blockNumber - point.blockNumber) * (block.timestamp - point.ts)) / (block.number - point.blockNumber);
            }
        }
        // Now dt contains info on how far are we beyond point
        return supplyLockedAt(point, point.ts + dt);
    }
}
