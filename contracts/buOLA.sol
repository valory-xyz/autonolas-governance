// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./interfaces/IErrors.sol";

/// @title Burnable Locked OLA Token - OLA burnable contract
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>

// Interface for IOLA burn functionality
interface IOLA {
    /// @dev Burns OLA tokens.
    /// @param amount OLA token amount to burn.
    function burn(uint256 amount) external;
}

// Struct for storing balance, lock and unlock time
// The struct size is one storage slot of uint256 (96 + 96 + 32 + 32)
struct LockedBalance {
    // Token amount locked. Initial OLA cap is 1 bn tokens, or 1e27.
    // After 10 years, the inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1
    uint96 amountLocked;
    // Token amount released
    uint96 amountReleased;
    // Lock time start
    uint32 start;
    // Lock end time
    // 2^32 - 1 is enough to count 136 years starting from the year of 1970. This counter is safe until the year of 2106
    uint32 end;
}

/// @notice This token supports the ERC20 interface specifications except for transfers.
contract buOLA is IErrors, IERC20, IERC165 {
    event Lock(address indexed account, uint256 amount, uint256 start, uint256 end);
    event Withdraw(address indexed account, uint256 amount, uint256 ts);
    event Revoke(address indexed account, uint256 amount, uint256 ts);
    event Burn(address indexed account, uint256 amount, uint256 ts);
    event Supply(uint256 prevSupply, uint256 curSupply);
    event OwnerUpdated(address indexed owner);

    // Locking step time
    uint32 internal constant STEP_TIME = 365 * 86400;
    // Maximum number of steps
    uint32 internal constant MAX_NUM_STEPS = 10;
    // Reentrancy lock
    uint256 private locked = 1;
    // Total token supply
    uint256 public supply;
    // Number of decimals
    uint8 public constant decimals = 18;

    // Token address
    address public immutable token;
    // Owner address
    address public owner;
    // Mapping of account address => LockedBalance
    mapping(address => LockedBalance) public mapLockedBalances;

    // Voting token name
    string public name;
    // Voting token symbol
    string public symbol;

    /// @dev Contract constructor
    /// @param _token Token address.
    /// @param _name Token name.
    /// @param _symbol Token symbol.
    constructor(address _token, string memory _name, string memory _symbol)
    {
        token = _token;
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
            revert ManagerOnly(msg.sender, owner);
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Deposits `amount` tokens for the `account` and locks for the `numSteps` time periods.
    /// @param account Target account address.
    /// @param amount Amount to deposit.
    /// @param numSteps Number of locking steps.
    function createLockFor(address account, uint256 amount, uint256 numSteps) external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;

        // Check if the account is zero
        if (account == address(0)) {
            revert ZeroAddress();
        }
        // Check if the amount is zero
        if (amount == 0) {
            revert ZeroValue();
        }
        // The locking makes sense for one step or more only
        if (numSteps == 0) {
            revert ZeroValue();
        }
        // Check the maximum number of steps
        if (numSteps > MAX_NUM_STEPS) {
            revert Overflow(numSteps, MAX_NUM_STEPS);
        }
        // Lock time is equal to the number of fixed steps multiply on a step time
        uint256 unlockTime = block.timestamp + uint256(STEP_TIME) * numSteps;
        // Max of 2^32 - 1 value, the counter is safe until the year of 2106
        if (unlockTime > type(uint32).max) {
            revert Overflow(unlockTime, type(uint32).max);
        }
        // After 10 years, the inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1 total supply
        if (amount > type(uint96).max) {
            revert Overflow(amount, type(uint96).max);
        }

        LockedBalance memory lockedBalance = mapLockedBalances[account];
        // The locked balance must be zero in order to start the lock
        if (lockedBalance.amountLocked > 0) {
            revert LockedValueNotZero(account, lockedBalance.amountLocked);
        }

        // Store the locked information for the account
        lockedBalance.start = uint32(block.timestamp);
        lockedBalance.end = uint32(unlockTime);
        lockedBalance.amountLocked = uint96(amount);
        mapLockedBalances[account] = lockedBalance;

        // Calculate total supply
        uint256 supplyBefore = supply;
        uint256 supplyAfter;
        // Cannot overflow because we do not add more tokens than the OLA supply
        unchecked {
            supplyAfter = supplyBefore + amount;
            supply = supplyAfter;
        }

        // OLA is a standard ERC20 token with a original function transfer() that returns bool
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed(token, msg.sender, address(this), amount);
        }

        emit Lock(account, amount, block.timestamp, unlockTime);
        emit Supply(supplyBefore, supplyAfter);

        locked = 1;
    }

    /// @dev Releases all matured tokens for `msg.sender`.
    function withdraw() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ReentrancyGuard();
        }
        locked = 2;

        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        if (lockedBalance.amountLocked > 0) {
            // Calculate the amount to release
            uint256 amount = _releasableAmount(lockedBalance);
            // Check if at least one locking step has passed
            if (amount == 0) {
                revert LockNotExpired(msg.sender, lockedBalance.end, block.timestamp);
            }

            uint256 supplyBefore = supply;
            uint256 supplyAfter;
            // This end time is greater than zero is withdraw was not fully completed
            if (lockedBalance.end > 0) {
                unchecked {
                    // Update the account locked amount.
                    // Cannot practically overflow since the amount to release is smaller than the locked amount
                    lockedBalance.amountReleased += uint96(amount);
                }
                // The balance is fully unlocked. Released amount must be equal to the locked one
                if ((lockedBalance.amountReleased + 1) > lockedBalance.amountLocked) {
                    mapLockedBalances[msg.sender] = LockedBalance(0, 0, 0, 0);
                } else {
                    mapLockedBalances[msg.sender] = lockedBalance;
                }
            } else {
                // This means revoke has been called on this account and the tokens must be burned
                uint256 amountBurn;
                unchecked {
                    // Locked amount cannot be smaller than the released amount
                    amountBurn = uint256(lockedBalance.amountLocked - lockedBalance.amountReleased);
                    supplyAfter = supplyAfter - amountBurn;
                }

                // Burn revoked tokens and set all the data to zero
                IOLA(token).burn(amountBurn);
                mapLockedBalances[msg.sender] = LockedBalance(0, 0, 0, 0);
                emit Burn(msg.sender, amountBurn, block.timestamp);
            }

            // The amount cannot be less than the total supply
            unchecked {
                supplyAfter = supplyBefore - amount;
                supply = supplyAfter;
            }

            emit Withdraw(msg.sender, amount, block.timestamp);
            emit Supply(supplyBefore, supplyAfter);

            bool success = IERC20(token).transfer(msg.sender, amount);
            if (!success) {
                revert TransferFailed(token, address(this), msg.sender, amount);
            }
        }
        locked = 1;
    }

    /// @dev Revoke and burn all non-matured tokens from the `account`.
    /// @param accounts Account addresses.
    function revoke(address[] memory accounts) external {
        // Check for the ownership
        if (owner != msg.sender) {
            revert ManagerOnly(msg.sender, owner);
        }

        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            LockedBalance memory lockedBalance = mapLockedBalances[account];

            // Get the amount to release
            uint256 amountRelease = _releasableAmount(lockedBalance);
            // This is the release amount that will be transferred to the account when they withdraw
            lockedBalance.amountReleased = uint96(amountRelease);
            // Termination state of the revoke procedure
            lockedBalance.end = 0;
            // Update the account data
            mapLockedBalances[account] = lockedBalance;

            emit Revoke(account, uint256(lockedBalance.amountLocked) - amountRelease, block.timestamp);
        }
    }

    /// @dev Gets the account locking balance.
    /// @param account Account address.
    /// @return balance Account balance.
    function balanceOf(address account) public view override returns (uint256 balance) {
        balance = uint256(mapLockedBalances[account].amountLocked - mapLockedBalances[account].amountReleased);
    }

    /// @dev Gets total token supply.
    /// @return Total token supply.
    function totalSupply() public view override returns (uint256) {
        return supply;
    }

    /// @dev Gets the account releasable amount.
    /// @param account Account address.
    /// @return amount Amount to release.
    function releasableAmount(address account) external view returns (uint256 amount) {
        LockedBalance memory lockedBalance = mapLockedBalances[account];
        amount = _releasableAmount(lockedBalance);
    }

    /// @dev Gets the account releasable amount.
    /// @param lockedBalance Account locked balance struct.
    /// @return amount Amount to release.
    function _releasableAmount(LockedBalance memory lockedBalance) private view returns (uint256 amount) {
        // If the end is equal 0, this balance is either left after revoke or expired
        if (lockedBalance.end == 0) {
            return lockedBalance.amountReleased;
        }
        // Number of steps
        uint32 numSteps;
        // Current locked time
        uint32 releasedSteps;
        // Time in the future will be greater than the start time
        unchecked {
            numSteps = (lockedBalance.end - lockedBalance.start) / STEP_TIME;
            releasedSteps = (uint32(block.timestamp) - lockedBalance.start) / STEP_TIME;
        }

        // If the number of release steps is greater than the number of steps, all the available tokens are unlocked
        if (releasedSteps > numSteps) {
            releasedSteps = numSteps;
        }

        // Calculate the amount to release
        amount = uint256(lockedBalance.amountLocked * releasedSteps / numSteps);
        amount -= uint256(lockedBalance.amountReleased);
    }

    /// @dev Gets the `account`'s locking end time.
    /// @param account Account address.
    /// @return unlockTime Maturity time.
    function lockedEnd(address account) external view returns (uint256 unlockTime) {
        unlockTime = uint256(mapLockedBalances[account].end);
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
