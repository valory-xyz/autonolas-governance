// The following code is from flattening this file: buOLA.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

// The following code is from flattening this import statement in: buOLA.sol
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-governance/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// The following code is from flattening this import statement in: buOLA.sol
// import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-governance/node_modules/@openzeppelin/contracts/utils/introspection/IERC165.sol
// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)


/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// The following code is from flattening this import statement in: buOLA.sol
// import "./interfaces/IErrors.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-governance/contracts/interfaces/IErrors.sol

/// @dev Errors.
interface IErrors {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Wrong hash format.
    /// @param hashFunctionProvided Hash function classification provided.
    /// @param hashFunctionNeeded Hash function classification needed.
    /// @param sizeProvided Size of a hash digest provided.
    /// @param sizeNeeded Size of a hash digest needed.
    error WrongHash(uint8 hashFunctionProvided, uint8 hashFunctionNeeded, uint8 sizeProvided, uint8 sizeNeeded);

    /// @dev Hash already exists in the records.
    error HashExists();

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev The provided string is empty.
    error EmptyString();

    /// @dev Component Id is not correctly provided for the current routine.
    /// @param componentId Component Id.
    error WrongComponentId(uint256 componentId);

    /// @dev Agent Id is not correctly provided for the current routine.
    /// @param agentId Component Id.
    error WrongAgentId(uint256 agentId);

    /// @dev Wrong length of two arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Numberf of values in a second array.
    error WrongArrayLength(uint256 numValues1, uint256 numValues2);

    /// @dev Canonical agent Id is not found.
    /// @param agentId Canonical agent Id.
    error AgentNotFound(uint256 agentId);

    /// @dev Component Id is not found.
    /// @param componentId Component Id.
    error ComponentNotFound(uint256 componentId);

    /// @dev Multisig threshold is out of bounds.
    /// @param currentThreshold Current threshold value.
    /// @param minThreshold Minimum possible threshold value.
    /// @param maxThreshold Maximum possible threshold value.
    error WrongThreshold(uint256 currentThreshold, uint256 minThreshold, uint256 maxThreshold);

    /// @dev Service Id is not found, although service Id might exist in the records.
    /// @dev serviceId Service Id.
    error ServiceNotFound(uint256 serviceId);

    /// @dev Service Id does not exist in registry records.
    /// @param serviceId Service Id.
    error ServiceDoesNotExist(uint256 serviceId);

    /// @dev Agent instance is already registered with a specified `operator`.
    /// @param operator Operator that registered an instance.
    error AgentInstanceRegistered(address operator);

    /// @dev Wrong operator is specified when interacting with a specified `serviceId`.
    /// @param serviceId Service Id.
    error WrongOperator(uint256 serviceId);

    /// @dev Operator has no registered instances in the service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    error OperatorHasNoInstances(address operator, uint256 serviceId);

    /// @dev Canonical `agentId` is not found as a part of `serviceId`.
    /// @param agentId Canonical agent Id.
    /// @param serviceId Service Id.
    error AgentNotInService(uint256 agentId, uint256 serviceId);

    /// @dev Zero value when it has to be different from zero.
    error ZeroValue();

    /// @dev Non-zero value when it has to be zero.
    error NonZeroValue();

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Token is non-transferable.
    /// @param account Token address.
    error NonTransferable(address account);

    /// @dev Token is non-delegatable.
    /// @param account Token address.
    error NonDelegatable(address account);

    /// @dev Service must be active.
    /// @param serviceId Service Id.
    error ServiceMustBeActive(uint256 serviceId);

    /// @dev Service must be inactive.
    /// @param serviceId Service Id.
    error ServiceMustBeInactive(uint256 serviceId);

    /// @dev Service termination block has been reached. Service is terminated.
    /// @param teminationBlock The termination block.
    /// @param curBlock Current block.
    /// @param serviceId Service Id.
    error ServiceTerminated(uint256 teminationBlock, uint256 curBlock, uint256 serviceId);

    /// @dev All the agent instance slots for a specific `serviceId` are filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsFilled(uint256 serviceId);

    /// @dev Agent instances for a specific `serviceId` are not filled.
    /// @param actual Current number of agent instances.
    /// @param maxNumAgentInstances Maximum number of agent instances to be filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsNotFilled(uint256 actual, uint256 maxNumAgentInstances, uint256 serviceId);

    /// @dev Wrong state of a service.
    /// @param state Service state.
    /// @param serviceId Service Id.
    error WrongServiceState(uint256 state, uint256 serviceId);

    /// @dev Only own service multisig is allowed.
    /// @param provided Provided address.
    /// @param expected Expected multisig address.
    /// @param serviceId Service Id.
    error OnlyOwnServiceMultisig(address provided, address expected, uint256 serviceId);

    /// @dev Fallback or receive function.
    error WrongFunction();

    /// @dev Token is disabled or not whitelisted.
    /// @param tokenAddress Address of a token.
    error UnauthorizedToken(address tokenAddress);

    /// @dev Multisig is not whitelisted.
    /// @param multisig Address of a multisig implementation.
    error UnauthorizedMultisig(address multisig);

    /// @dev Account is not whitelisted.
    /// @param account Account address.
    error UnauthorizedAccount(address account);

    /// @dev Provided token address is incorrect.
    /// @param provided Provided token address.
    /// @param expected Expected token address.
    error WrongTokenAddress(address provided, address expected);

    /// @dev The product is expired.
    /// @param tokenAddress Address of a token.
    /// @param productId Product Id.
    /// @param deadline The program expiry time.
    /// @param curTime Current timestamp.
    error ProductExpired(address tokenAddress, uint256 productId, uint256 deadline, uint256 curTime);

    /// @dev The product supply is low for the requested payout.
    /// @param tokenAddress Address of a token.
    /// @param productId Product Id.
    /// @param requested Requested payout.
    /// @param actual Actual supply left.
    error ProductSupplyLow(address tokenAddress, uint256 productId, uint256 requested, uint256 actual);

    /// @dev Minting is rejected due to the requested amount bigger than the current inflation policy cap.
    /// @param amount Amount of tokens to mint.
    error MintRejectedByInflationPolicy(uint256 amount);

    /// @dev Incorrect amount received / provided.
    /// @param provided Provided amount is lower.
    /// @param expected Expected amount.
    error AmountLowerThan(uint256 provided, uint256 expected);

    /// @dev Wrong amount received / provided.
    /// @param provided Provided amount.
    /// @param expected Expected amount.
    error WrongAmount(uint256 provided, uint256 expected);

    /// @dev Insufficient token allowance.
    /// @param provided Provided amount.
    /// @param expected Minimum expected amount.
    error InsufficientAllowance(uint256 provided, uint256 expected);

    /// @dev Incorrect deposit provided for the registration activation.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectRegistrationDepositValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Insufficient value provided for the agent instance bonding.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectAgentBondingValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param value Value.
    error TransferFailed(address token, address from, address to, uint256 value);

    /// @dev No existing lock value is found.
    /// @param account Address that is checked for the locked value.
    error NoValueLocked(address account);

    /// @dev Locked value is not zero.
    /// @param account Address that is checked for the locked value.
    /// @param amount Locked amount.
    error LockedValueNotZero(address account, uint256 amount);

    /// @dev Value lock is expired.
    /// @param account Address that is checked for the locked value.
    /// @param deadline The lock expiration deadline.
    /// @param curTime Current timestamp.
    error LockExpired(address account, uint256 deadline, uint256 curTime);

    /// @dev Value lock is not expired.
    /// @param account Address that is checked for the locked value.
    /// @param deadline The lock expiration deadline.
    /// @param curTime Current timestamp.
    error LockNotExpired(address account, uint256 deadline, uint256 curTime);

    /// @dev Provided unlock time is incorrect.
    /// @param account Address that is checked for the locked value.
    /// @param minUnlockTime Minimal unlock time that can be set.
    /// @param providedUnlockTime Provided unlock time.
    error UnlockTimeIncorrect(address account, uint256 minUnlockTime, uint256 providedUnlockTime);

    /// @dev Provided unlock time is bigger than the maximum allowed.
    /// @param account Address that is checked for the locked value.
    /// @param maxUnlockTime Max unlock time that can be set.
    /// @param providedUnlockTime Provided unlock time.
    error MaxUnlockTimeReached(address account, uint256 maxUnlockTime, uint256 providedUnlockTime);

    /// @dev Provided block number is incorrect (has not been processed yet).
    /// @param providedBlockNumber Provided block number.
    /// @param actualBlockNumber Actual block number.
    error WrongBlockNumber(uint256 providedBlockNumber, uint256 actualBlockNumber);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();
}


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
    /// @notice Tokens are taken from `msg.sender`'s balance.
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
                uint256 amountBurn;
                unchecked {
                    // Locked amount cannot be smaller than the released amount
                    amountBurn = uint256(lockedBalance.amountLocked - lockedBalance.amountReleased);
                    supplyAfter = supplyBefore - amountBurn;
                }

                // Burn revoked tokens and set all the data to zero
                IOLA(token).burn(amountBurn);
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



