// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./ERC20VotesCustomUpgradeable.sol";
import "../interfaces/IErrors.sol";

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
interface SmartWalletChecker {
    function check(address addr) external returns (bool);
}

struct Point {
    int128 bias;
    int128 slope; // dweight / dt
    uint256 ts;
    uint256 blk; // block
}
/* We cannot really do block numbers per se b/c slope is per time, not per block
* and per block could be fairly bad b/c Ethereum changes blocktimes.
* What we can do is to extrapolate ***At functions */

struct LockedBalance {
    int128 amount;
    uint256 end;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract VotingEscrow is IErrors, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC20VotesCustomUpgradeable {
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

    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    int128 internal constant iMAXTIME = 4 * 365 * 86400;
    uint256 internal constant MULTIPLIER = 1 ether;

    address immutable public token;
    uint256 public supply;
    mapping(address => LockedBalance) public locked;

    uint256 public epoch;
    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(address => Point[1000000000]) public userPointHistory; // user -> Point[user_epoch]
    mapping(uint256 => int128) public slopeChanges; // time -> signed slope change
    mapping(address => uint256) public userPointEpoch;

    // Aragon's view methods for compatibility
    address public controller;
    bool public transfersEnabled;

    uint8 _decimals;
    string public version;

    // Checker for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    address public futureSmartWalletChecker;
    address public smartWalletChecker;

    /// @dev Contract constructor
    /// @param tokenAddr token address
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _version Contract version - required for Aragon compatibility
    constructor(address tokenAddr, string memory _name, string memory _symbol, string memory _version) initializer {
        __ERC20Permit_init(_name);
        __ERC20_init(_name, _symbol);
        token = tokenAddr;
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;
        version = _version;
        _decimals = ERC20(tokenAddr).decimals();
        if (_decimals > 255) {
            revert Overflow(uint256(_decimals), 255);
        }
    }

    /// @dev Defines decimals.
    /// @return Token decimals.
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev Bans transfers of this token.
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        revert NonTransferrable(address(this));
    }

    /// @dev Bans approval of this token.
    function _approve(address owner, address spender, uint256 amount) internal override {
        revert NonTransferrable(address(this));
    }

    /// @dev Set an external contract to check for approved smart contract wallets
    /// @param addr Address of Smart contract checker
    function commitSmartWalletChecker(address addr) external onlyOwner {
        futureSmartWalletChecker = addr;
    }


    /// @dev Apply setting external contract to check approved smart contract wallets
    function applySmartWalletChecker() external onlyOwner {
        smartWalletChecker = futureSmartWalletChecker;
    }


    /// @dev Check if the call is from a whitelisted smart contract, revert if not
    /// @param addr Address to be checked
    function assertNotContract(address addr) internal {
        if (addr != tx.origin) {
            address checker = smartWalletChecker;
            require(checker != address(0) && SmartWalletChecker(checker).check(addr),
                "SC depositors not allowed");
        }
    }

    /// @dev Get the most recently recorded rate of voting power decrease for `addr`
    /// @param addr Address of the user wallet
    /// @return Value of the slope
    function getLastUserSlope(address addr) external view returns (int128) {
        uint256 uepoch = userPointEpoch[addr];
        return userPointHistory[addr][uepoch].slope;
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
    /// @param addr User's wallet address. No user checkpoint if 0x0
    /// @param oldLocked Pevious locked amount / end lock time for the user
    /// @param newLocked New locked amount / end lock time for the user
    function _checkpoint(
        address addr,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldDSlope = 0;
        int128 newDSlope = 0;
        uint256 _epoch = epoch;

        if (addr != address(0)) {
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

        Point memory lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initialLastPoint = lastPoint;
        uint256 block_slope = 0; // dblock/dt
        if (block.timestamp > lastPoint.ts) {
            block_slope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
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
                lastPoint.blk = initialLastPoint.blk + (block_slope * (tStep - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (tStep == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    pointHistory[_epoch] = lastPoint;
                }
            }
        }

        epoch = _epoch;
        // Now pointHistory is filled until t=now

        if (addr != address(0)) {
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

        if (addr != address(0)) {
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
            uint256 user_epoch = userPointEpoch[addr] + 1;

            userPointEpoch[addr] = user_epoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[addr][user_epoch] = uNew;
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
            if (!ERC20(token).transferFrom(from, address(this), _value)) {
                revert TransferFailed(token, from, address(this), _value);
            }
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

        assert(ERC20(token).transfer(msg.sender, value));

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /// @dev Binary search to estimate timestamp for block number
    /// @param _block Block to find
    /// @param maxEpoch Don't go beyond this epoch
    /// @return Approximate timestamp for block
    function _findBlockEpoch(uint256 _block, uint256 maxEpoch) internal view returns (uint256) {
        // Binary search
        uint256 _min = 0;
        uint256 _max = maxEpoch;
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    /// @dev Get the current voting power for `addr` and time `t`
    /// @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
    /// @param addr User wallet address
    /// @param _t Epoch time to return voting power at
    /// @return User voting power
    function _balanceOf(address addr, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[addr];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = userPointHistory[addr][_epoch];
            lastPoint.bias -= lastPoint.slope * int128(int256(_t) - int256(lastPoint.ts));
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint256(int256(lastPoint.bias));
        }
    }

    /// @dev Get the current voting power for `addr`
    function balanceOf(address addr) public view override returns (uint256) {
        return _balanceOf(addr, block.timestamp);
    }

    /// @dev Measure voting power of `addr` at block height `_block`
    /// @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
    /// @param addr User's wallet address
    /// @param _block Block to calculate the voting power at
    /// @return Voting power
    function balanceOfAt(address addr, uint256 _block) public view override returns (uint256) {
        if (_block > block.number) {
            revert WrongBlockNumber(_block, block.number);
        }

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[addr];
        for (uint256 i = 0; i < 128; ++i) {
            // Will be always enough for 128-bit numbers
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[addr][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory uPoint = userPointHistory[addr][_min];

        uint256 maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_block, maxEpoch);
        Point memory point0 = pointHistory[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;
        if (_epoch < maxEpoch) {
            Point memory point1 = pointHistory[_epoch + 1];
            d_block = point1.blk - point0.blk;
            d_t = point1.ts - point0.ts;
        } else {
            d_block = block.number - point0.blk;
            d_t = block.timestamp - point0.ts;
        }
        uint256 block_time = point0.ts;
        if (d_block != 0) {
            block_time += (d_t * (_block - point0.blk)) / d_block;
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
    function supplyAt(Point memory point, uint256 t) internal view returns (uint256) {
        Point memory lastPoint = point;
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

    /// @dev Calculate total voting power at time `t`. Adheres to the ERC20 `totalSupply` for Aragon compatibility
    /// @return Total voting power
    function totalSupplyAtT(uint256 t) public view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[_epoch];
        return supplyAt(lastPoint, t);
    }

    /// @dev Calculate total voting power
    /// @return Total voting power
    function totalSupply() public view override returns (uint256) {
        return totalSupplyAtT(block.timestamp);
    }

    /// @dev Calculate total voting power at some point in the past
    /// @param _block Block to calculate the total voting power at
    /// @return Total voting power at `_block`
    function totalSupplyAt(uint256 _block) public view override returns (uint256) {
        if (_block > block.number) {
            revert WrongBlockNumber(_block, block.number);
        }
        uint256 _epoch = epoch;
        uint256 target_epoch = _findBlockEpoch(_block, _epoch);

        Point memory point = pointHistory[target_epoch];
        uint256 dt = 0;
        if (target_epoch < _epoch) {
            Point memory pointNext = pointHistory[target_epoch + 1];
            if (point.blk != pointNext.blk) {
                dt = ((_block - point.blk) * (pointNext.ts - point.ts)) / (pointNext.blk - point.blk);
            }
        } else {
            if (point.blk != block.number) {
                dt = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
            }
        }
        // Now dt contains info on how far are we beyond point
        return supplyAt(point, point.ts + dt);
    }

    /// @dev Dummy method required for Aragon compatibility
    function changeController(address _newController) external {
        require(msg.sender == controller, "No access");
        controller = _newController;
    }
}
