// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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
contract Sale is IErrors, IERC20, IERC165 {
    event LockVE(address indexed account, uint256 amount, uint256 timePeriod);
    event LockBU(address indexed account, uint256 amount, uint256 numSteps);
    event ClaimVE(address indexed account, uint256 amount, uint256 timePeriod);
    event ClaimBU(address indexed account, uint256 amount, uint256 numSteps);
    event Supply(uint256 prevSupply, uint256 curSupply);
    event OwnerUpdated(address indexed owner);

    // Locking step time (synced with buOLAS `STEP_TIME`)
    uint32 internal constant STEP_TIME = 365 * 86400;

    // Reentrancy lock
    uint256 private locked = 1;
    // Total token supply
    uint256 public supply;
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

        uint256 supplyBefore = supply;
        uint256 supplyAfter = supplyBefore;
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

            // Update supply and emit the lock
            supplyAfter += veAmounts[i];
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

            // Update supply and emit the lock
            supplyAfter += buAmounts[i];
            emit LockBU(buAccounts[i], buAmounts[i], buNumSteps[i]);
        }

        emit Supply(supplyBefore, supplyAfter);
    }

    /// @dev Claims token lock for `msg.sender` into veOLAS contract.
    function claimVE() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;

        // Get the balance, lock time and call the veOLAS locking function
        LockedBalance memory lockedBalance = mapVE[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(veToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            uint256 supplyBefore = supply;
            uint256 supplyAfter = supplyBefore - uint256(lockedBalance.amount);

            emit ClaimVE(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            emit Supply(supplyBefore, supplyAfter);
        }

        locked = 1;
    }

    /// @dev Claims token lock for `msg.sender` into buOLAS contract.
    function claimBU() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;

        // Get the balance, lock time and call the veOLAS locking function
        LockedBalance memory lockedBalance = mapBU[msg.sender];
        if (lockedBalance.amount > 0) {
            ILOCK(buToken).createLockFor(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            uint256 supplyBefore = supply;
            uint256 supplyAfter = supplyBefore - uint256(lockedBalance.amount);

            emit ClaimBU(msg.sender, uint256(lockedBalance.amount), uint256(lockedBalance.period));
            emit Supply(supplyBefore, supplyAfter);
        }

        locked = 1;
    }

    /// @dev Gets the account locking balance.
    /// @param account Account address.
    /// @return balance Account balance.
    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = uint256(mapVE[account].amount);
        // If there is no balance in veOLAS lock, check the buOLAS one
        if (balance == 0) {
            balance = uint256(mapBU[account].amount);
        }
    }

    /// @dev Gets total token supply.
    /// @return Total token supply.
    function totalSupply() public view override returns (uint256) {
        return supply;
    }

    /// @dev Gets the `account`'s locking time period for veOLAS.
    /// @param account Account address.
    /// @return period Lock time period.
    function lockedTimePeriod(address account) external view returns (uint256 period) {
        period = uint256(mapVE[account].period);
    }

    /// @dev Gets the `account`'s locking number of steps for buOLAS.
    /// @param account Account address.
    /// @return numSteps Lock number of steps.
    function lockedNumSteps(address account) external view returns (uint256 numSteps) {
        numSteps = uint256(mapBU[account].period);
    }

    /// @dev Gets information about the interface support.
    /// @param interfaceId A specified interface Id.
    /// @return True if this contract implements the interface defined by interfaceId.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC20).interfaceId;
    }

    /// @dev Reverts the transfer of this token.
    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Reverts the approval of this token.
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Reverts the transferFrom of this token.
    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        revert NonTransferable(address(this));
    }

    /// @dev Reverts the allowance of this token.
    function allowance(address owner, address spender) external view virtual override returns (uint256)
    {
        revert NonTransferable(address(this));
    }
}
