// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

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
