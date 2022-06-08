// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./interfaces/IErrors.sol";

/// @title Sale - OLAS sale contract
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>

// Interface for the lock functionality
interface ILOCK {
    /// @dev Deposits `amount` tokens for `account` and locks for `unlockTime` time or number of periods.
    /// @param account Account address.
    /// @param amount Amount to deposit.
    /// @param unlockTime Time or number of time periods when tokens unlock.
    function createLockFor(address account, uint256 amount, uint256 unlockTime) external;
}

// Interface for the OLAS token allowance increase
interface IOLAS {
    /// @dev Increases the allowance of another account over their tokens.
    /// @param spender Account that tokens are approved for.
    /// @param amount Amount to increase approval by.
    /// @return True if the operation succeeded.
    function increaseAllowance(address spender, uint256 amount) external returns (bool);
}

// Struct for storing claimable balance, lock and unlock time
// The struct size is one storage slot of uint256 (128 + 64 + padding)
struct ClaimableBalance {
    // Token amount to be locked. Initial OLAS cap is 1 bn tokens, or 1e27.
    // After 10 years, the inflation rate is 2% per year. It would take 1340+ years to reach 2^128 - 1 total supply
    uint128 amount;
    // Lock time period or number of steps
    // 2^64 - 1 value, which is bigger than the end of time in seconds while Earth is spinning
    uint64 period;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract Sale is IErrors {
    event CreateVE(address indexed account, uint256 amount, uint256 timePeriod);
    event CreateBU(address indexed account, uint256 amount, uint256 numSteps);
    event ClaimVE(address indexed account, uint256 amount, uint256 timePeriod);
    event ClaimBU(address indexed account, uint256 amount, uint256 numSteps);
    event OwnerUpdated(address indexed owner);

    // Maximum number of steps for buOLAS (synced with buOLAS `MAX_NUM_STEPS`)
    uint256 internal constant MAX_NUM_STEPS = 10;
    // Minimum lock time for veOLAS (1 year)
    uint256 internal constant MINTIME = 365 * 86400;
    // Maximum lock time for veOLAS (synced with veOLAS `MAXTIME`)
    uint256 internal constant MAXTIME = 4 * 365 * 86400;
    // Reentrancy lock
    uint256 private locked = 1;
    // OLAS token address
    address public immutable olasToken;
    // veOLAS token address
    address public immutable veToken;
    // buOLAS token address
    address public immutable buToken;
    // Owner address
    address public owner;
    // Mapping of account address => ClaimableBalance to lock for veOLAS
    mapping(address => ClaimableBalance) public mapVE;
    // Mapping of account address => ClaimableBalance to lock for buOLAS
    mapping(address => ClaimableBalance) public mapBU;

    /// @dev Contract constructor
    /// @param _olasToken OLAS token address.
    /// @param _veToken veOLAS token address.
    /// @param _buToken buOLAS token address.
    constructor(address _olasToken, address _veToken, address _buToken)
    {
        olasToken = _olasToken;
        veToken = _veToken;
        buToken = _buToken;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Creates schedules of locks for provided accounts depending on the lock time.
    /// @param veAccounts Accounts for veOLAS locks.
    /// @param veAmounts Amounts for `veAccounts`.
    /// @param veLockTimes Lock time for `veAccounts`.
    /// @param buAccounts Accounts for buOLAS locks.
    /// @param buAmounts Amounts for `buAccounts`.
    /// @param buNumSteps Lock time for `buAccounts`.
    function createBalancesFor(
        address[] memory veAccounts,
        uint256[] memory veAmounts,
        uint256[] memory veLockTimes,
        address[] memory buAccounts,
        uint256[] memory buAmounts,
        uint256[] memory buNumSteps
    ) external {
        // Check for the ownership
        if (owner != msg.sender) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check that all the corresponding arrays have the same length
        if (veAccounts.length != veAmounts.length || veAccounts.length != veLockTimes.length) {
            revert WrongArrayLength(veAccounts.length, veAmounts.length);
        }
        if (buAccounts.length != buAmounts.length || buAccounts.length != buNumSteps.length) {
            revert WrongArrayLength(buAccounts.length, buAmounts.length);
        }

        uint256 allowanceVE;
        uint256 allowanceBU;

        // Create lock-ready structures for veOLAS
        for (uint256 i = 0; i < veAccounts.length; ++i) {
            // Check for the zero addresses
            if (veAccounts[i] == address(0)) {
                revert ZeroAddress();
            }
            // Check for other zero values
            if (veAmounts[i] == 0) {
                revert ZeroValue();
            }
            // Check for the amount bounds
            if (veAmounts[i] > type(uint128).max) {
                revert Overflow(veAmounts[i], type(uint128).max);
            }
            // Check the end of a lock time
            if (veLockTimes[i] < MINTIME) {
                revert UnlockTimeIncorrect(veAccounts[i], MINTIME, veLockTimes[i]);
            }
            if (veLockTimes[i] > MAXTIME) {
                revert MaxUnlockTimeReached(veAccounts[i], MAXTIME, veLockTimes[i]);
            }
            // Check if the lock has already been placed
            ClaimableBalance memory lockedBalance = mapVE[veAccounts[i]];
            if (lockedBalance.amount > 0) {
                revert NonZeroValue();
            }

            // Update allowance, push values to the dedicated locking slot
            allowanceVE += veAmounts[i];
            lockedBalance.amount = uint128(veAmounts[i]);
            lockedBalance.period = uint64(veLockTimes[i]);
            mapVE[veAccounts[i]] = lockedBalance;

            emit CreateVE(veAccounts[i], veAmounts[i], veLockTimes[i]);
        }

        // Create lock-ready structures for buOLAS
        for (uint256 i = 0; i < buAccounts.length; ++i) {
            // Check for the zero addresses
            if (buAccounts[i] == address(0)) {
                revert ZeroAddress();
            }
            // Check for other zero values
            if (buAmounts[i] == 0 || buNumSteps[i] == 0) {
                revert ZeroValue();
            }
            // Check for the amount bounds
            if (buAmounts[i] > type(uint128).max) {
                revert Overflow(buAmounts[i], type(uint128).max);
            }
            // Check for the number of lock steps
            if (buNumSteps[i] > MAX_NUM_STEPS) {
                revert Overflow(buNumSteps[i], MAX_NUM_STEPS);
            }
            // Check if the lock has already been placed
            ClaimableBalance memory lockedBalance = mapBU[buAccounts[i]];
            if (lockedBalance.amount > 0) {
                revert NonZeroValue();
            }

            // Update allowance, push values to the dedicated locking slot
            allowanceBU += buAmounts[i];
            lockedBalance.amount = uint128(buAmounts[i]);
            lockedBalance.period = uint64(buNumSteps[i]);
            mapBU[buAccounts[i]] = lockedBalance;

            emit CreateBU(buAccounts[i], buAmounts[i], buNumSteps[i]);
        }

        // Increase allowances
        if (allowanceVE > 0) {
            IOLAS(olasToken).increaseAllowance(address(veToken), allowanceVE);
        }
        if (allowanceBU > 0) {
            IOLAS(olasToken).increaseAllowance(address(buToken), allowanceBU);
        }
    }

    /// @dev Claims token lock for `msg.sender` into veOLAS and / or buOLAS contract(s).
    function claim() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;

        // Get the balance, lock time and call the veOLAS locking function
        ClaimableBalance memory lockedBalance = mapVE[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(veToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            mapVE[msg.sender] = ClaimableBalance(0, 0);
            emit ClaimVE(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
        }

        lockedBalance = mapBU[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(buToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            mapBU[msg.sender] = ClaimableBalance(0, 0);
            emit ClaimBU(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
        }

        locked = 1;
    }

    /// @dev Gets the veOLAS claim status.
    /// @param account Account address.
    /// @return status True if the balance is not zero.
    function isClaimableVE(address account) external view returns (bool status) {
        uint256 balance = uint256(mapVE[account].amount);
        if (balance > 0) {
            status = true;
        }
    }

    /// @dev Gets the buOLAS claim status.
    /// @param account Account address.
    /// @return status True if the balance is not zero.
    function isClaimableBU(address account) external view returns (bool status) {
        uint256 balance = uint256(mapBU[account].amount);
        if (balance > 0) {
            status = true;
        }
    }
}
