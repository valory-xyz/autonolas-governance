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

// Struct for storing balance, lock and unlock time
// The struct size is one storage slot of uint256 (128 + 64 + padding)
struct LockedBalance {
    // Token amount locked. Initial OLAS cap is 1 bn tokens, or 1e27.
    // After 10 years, the inflation rate is 2% per year. It would take 1340+ years to reach 2^128 - 1 total supply
    uint128 amount;
    // Lock time period or number of steps
    // 2^64 - 1 value, which is bigger than the end of time in seconds while Earth is spinning
    uint64 period;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract Sale is IErrors {
    event LockVE(address indexed account, uint256 amount, uint256 timePeriod);
    event LockBU(address indexed account, uint256 amount, uint256 numSteps);
    event ClaimVE(address indexed account, uint256 amount, uint256 timePeriod);
    event ClaimBU(address indexed account, uint256 amount, uint256 numSteps);
    event OwnerUpdated(address indexed owner);

    // Locking step time (synced with buOLAS `STEP_TIME`)
    uint32 internal constant STEP_TIME = 365 * 86400;

    // Reentrancy lock
    uint256 private locked = 1;
    // Number of decimals
    uint8 public constant decimals = 18;

    // veOLAS token address
    address public immutable veToken;
    // buOLAS token address
    address public immutable buToken;
    // Owner address
    address public owner;
    // Mapping of account address => LockedBalance to lock for veOLAS
    mapping(address => LockedBalance) public mapVE;
    // Mapping of account address => LockedBalance to lock for buOLAS
    mapping(address => LockedBalance) public mapBU;

    // Token name
    string public name;
    // Token symbol
    string public symbol;

    /// @dev Contract constructor
    /// @param _veToken veOLAS token address.
    /// @param _buToken buOLAS token address.
    /// @param _name Token name.
    /// @param _symbol Token symbol.
    constructor(address _veToken, address _buToken, string memory _name, string memory _symbol)
    {
        veToken = _veToken;
        buToken = _buToken;
        name = _name;
        symbol = _symbol;
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
    function createLocksFor(
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
        if (veAccounts.length != veAmounts.length && veAccounts.length != veLockTimes.length) {
            revert WrongArrayLength(veAccounts.length, veAmounts.length);
        }
        if (buAccounts.length != buAmounts.length && buAccounts.length != buNumSteps.length) {
            revert WrongArrayLength(buAccounts.length, buAmounts.length);
        }

        // Create lock-ready structures for veOLAS
        for (uint256 i = 0; i < veAccounts.length; ++i) {
            // Check for the zero addresses
            if (veAccounts[i] == address(0)) {
                revert ZeroAddress();
            }
            // Check the end of a lock time
            uint256 unlockTime = block.timestamp + veLockTimes[i];
            if (unlockTime > type(uint64).max) {
                revert Overflow(unlockTime, type(uint64).max);
            }
            // Check for the amount bounds
            if (veAmounts[i] > type(uint128).max) {
                revert Overflow(veAmounts[i], type(uint128).max);
            }
            // Check if the lock has already been placed
            LockedBalance memory lockedBalance = mapVE[veAccounts[i]];
            if (lockedBalance.amount > 0) {
                revert NonZeroValue();
            }

            // Push values to the dedicated locking slot
            lockedBalance.amount = uint128(veAmounts[i]);
            lockedBalance.period = uint64(veLockTimes[i]);
            mapVE[veAccounts[i]] = lockedBalance;

            emit LockVE(veAccounts[i], veAmounts[i], veLockTimes[i]);
        }

        // Create lock-ready structures for buOLAS
        for (uint256 i = 0; i < buAccounts.length; ++i) {
            // Check for the zero addresses
            if (buAccounts[i] == address(0)) {
                revert ZeroAddress();
            }
            // Lock time is equal to the number of fixed steps multiply on a step time
            uint256 unlockTime = block.timestamp + uint256(STEP_TIME) * buNumSteps[i];
            // Check for the time lock bounds
            if (unlockTime > type(uint64).max) {
                revert Overflow(unlockTime, type(uint64).max);
            }
            // Check for the amount bounds
            if (buAmounts[i] > type(uint128).max) {
                revert Overflow(buAmounts[i], type(uint128).max);
            }
            // Check if the lock has already been placed
            LockedBalance memory lockedBalance = mapBU[buAccounts[i]];
            if (lockedBalance.amount > 0) {
                revert NonZeroValue();
            }
            
            // Push values to the dedicated locking slot
            lockedBalance.amount = uint128(buAmounts[i]);
            lockedBalance.period = uint64(buNumSteps[i]);
            mapBU[buAccounts[i]] = lockedBalance;

            emit LockBU(buAccounts[i], buAmounts[i], buNumSteps[i]);
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
        LockedBalance memory lockedBalance = mapVE[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(veToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            mapVE[msg.sender] = LockedBalance(0, 0);
            emit ClaimVE(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
        }

        lockedBalance = mapBU[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(buToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            mapBU[msg.sender] = LockedBalance(0, 0);
            emit ClaimBU(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
        }

        locked = 1;
    }
}
