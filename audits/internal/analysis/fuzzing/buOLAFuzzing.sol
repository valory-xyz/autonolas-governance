// The following code is from flattening this file: buOLA.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

// The following code is from flattening this import statement in: buOLA.sol
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-governance/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)



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
contract buOLAFuzzing  {
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
    address public token;
    // Owner address
    address public owner;
    // Mapping of account address => LockedBalance
    mapping(address => LockedBalance) public mapLockedBalances;

    // Voting token name
    string public name;
    // Voting token symbol
    string public symbol;

    /// Echidna invariant
    bool public cond = true;

    /// @dev Contract constructor
    constructor()
    {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        if (newOwner == address(0)) {
            revert ();
        }

        if (msg.sender != owner) {
            revert ();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Deposits `amount` tokens for the `account` and locks for the `numSteps` time periods.
    /// @notice Tokens are taken from `msg.sender`'s balance.
    /// @param account Target account address.
    /// @param amount Amount to deposit.
    /// @param numSteps Number of locking steps.
    function createLockFor(address account, uint256 amount, uint256 numSteps) external {
        // Reentrancy guard
        if (locked > 1) {
            revert ();
        }
        locked = 2;

        // Check if the account is zero
        if (account == address(0)) {
            revert ();
        }
        // Check if the amount is zero
        if (amount == 0) {
            revert ();
        }
        // The locking makes sense for one step or more only
        if (numSteps == 0) {
            revert ();
        }
        // Check the maximum number of steps
        if (numSteps > MAX_NUM_STEPS) {
            revert ();
        }
        // Lock time is equal to the number of fixed steps multiply on a step time
        uint256 unlockTime = block.timestamp + uint256(STEP_TIME) * numSteps;
        // Max of 2^32 - 1 value, the counter is safe until the year of 2106
        if (unlockTime > type(uint32).max) {
            revert ();
        }
        // After 10 years, the inflation rate is 2% per year. It would take 220+ years to reach 2^96 - 1 total supply
        if (amount > type(uint96).max) {
            revert ();
        }

        LockedBalance memory lockedBalance = mapLockedBalances[account];
        // The locked balance must be zero in order to start the lock
        if (lockedBalance.amountLocked > 0) {
            revert ();
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

        emit Lock(account, amount, block.timestamp, unlockTime);
        emit Supply(supplyBefore, supplyAfter);

        locked = 1;
    }

    /// @dev Releases all matured tokens for `msg.sender`.
    function withdraw() external {
        // Reentrancy guard
        if (locked > 1) {
            revert ();
        }
        locked = 2;
        uint256 amountBurn;

        LockedBalance memory lockedBalance = mapLockedBalances[msg.sender];
        if (lockedBalance.amountLocked > 0) {
            // Calculate the amount to release
            uint256 amount = _releasableAmount(lockedBalance);
            // Check if at least one locking step has passed
            if (amount == 0) {
                revert ();
            }

            uint256 supplyBefore = supply;
            uint256 supplyAfter = supplyBefore;
            // End time is greater than zero if withdraw was not fully completed and `revoke` was not called on the account
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
                // This means revoke has been called on this account and some tokens must be burned
                
                unchecked {
                    // Locked amount cannot be smaller than the released amount
                    amountBurn = uint256(lockedBalance.amountLocked - lockedBalance.amountReleased);
                    supplyAfter = supplyBefore - amountBurn;
                }

                // Burn revoked tokens and set all the data to zero
                // IOLA(token).burn(amountBurn);
                mapLockedBalances[msg.sender] = LockedBalance(0, 0, 0, 0);
                emit Burn(msg.sender, amountBurn, block.timestamp);
            }

            // The amount cannot be less than the total supply
            unchecked {
                supplyAfter -= amount;
                supply = supplyAfter;
            }

            emit Withdraw(msg.sender, amount, block.timestamp);
            emit Supply(supplyBefore, supplyAfter);

        }

        if(amountBurn > lockedBalance.amountLocked) {
            // echidna_test: PASSED!
            // cond = false;
        }

        if(lockedBalance.amountReleased > lockedBalance.amountLocked) {
            // echidna_test: PASSED!
            // cond = false;
        }

        if(lockedBalance.amountReleased == lockedBalance.amountLocked && lockedBalance.end > 0) {
            // echidna_test: PASSED!
            // cond = false;
        }

        if(lockedBalance.amountReleased == lockedBalance.amountLocked && lockedBalance.end == 0 && lockedBalance.amountLocked > 0) {
            // echidna_test: PASSED!
            // cond = false;
        }

        locked = 1;
    }

    /// @dev Revoke and burn all non-matured tokens from the `account`.
    /// @param accounts Account addresses.
    function revoke(address[] memory accounts) external {
        // Check for the ownership
        if (owner != msg.sender) {
            revert ();
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
    function balanceOf(address account) public view returns (uint256 balance) {
        LockedBalance memory lockedBalance = mapLockedBalances[account];
        // If the end is equal 0, this balance is either left after revoke or expired
        if (lockedBalance.end == 0) {
            // The maximum balance in this case is the released amount value
            balance = uint256(lockedBalance.amountReleased);
        } else {
            // Otherwise the balance is the difference between locked and released amounts
            balance = uint256(lockedBalance.amountLocked - lockedBalance.amountReleased);
        }
    }

    /// @dev Gets total token supply.
    /// @return Total token supply.
    function totalSupply() public view returns (uint256) {
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
        if ((releasedSteps + 1) > numSteps) {
            // Return the remainder from the last release since it's the last one
            unchecked {
                amount = uint256(lockedBalance.amountLocked - lockedBalance.amountReleased);
            }
        } else {
            // Calculate the amount to release
            unchecked {
                amount = uint256(lockedBalance.amountLocked * releasedSteps / numSteps);
                amount -= uint256(lockedBalance.amountReleased);
            }
        }
    }

    /// @dev Gets the `account`'s locking end time.
    /// @param account Account address.
    /// @return unlockTime Maturity time.
    function lockedEnd(address account) external view returns (uint256 unlockTime) {
        unlockTime = uint256(mapLockedBalances[account].end);
    }

    /// @dev Echidna fuzzer
    function echidna_test() public returns (bool) {
        return(cond);
    }
}




