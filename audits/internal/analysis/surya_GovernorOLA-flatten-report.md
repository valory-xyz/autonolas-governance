## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| GovernorOLA-flatten.sol | 7b24816396515d1a6a274a0ecb972aafe5d14510 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IERC721Receiver** | Interface |  |||
| └ | onERC721Received | External ❗️ | 🛑  |NO❗️ |
||||||
| **IERC165** | Interface |  |||
| └ | supportsInterface | External ❗️ |   |NO❗️ |
||||||
| **IERC1155Receiver** | Interface | IERC165 |||
| └ | onERC1155Received | External ❗️ | 🛑  |NO❗️ |
| └ | onERC1155BatchReceived | External ❗️ | 🛑  |NO❗️ |
||||||
| **Strings** | Library |  |||
| └ | toString | Internal 🔒 |   | |
| └ | toHexString | Internal 🔒 |   | |
| └ | toHexString | Internal 🔒 |   | |
||||||
| **ECDSA** | Library |  |||
| └ | _throwError | Private 🔐 |   | |
| └ | tryRecover | Internal 🔒 |   | |
| └ | recover | Internal 🔒 |   | |
| └ | tryRecover | Internal 🔒 |   | |
| └ | recover | Internal 🔒 |   | |
| └ | tryRecover | Internal 🔒 |   | |
| └ | recover | Internal 🔒 |   | |
| └ | toEthSignedMessageHash | Internal 🔒 |   | |
| └ | toEthSignedMessageHash | Internal 🔒 |   | |
| └ | toTypedDataHash | Internal 🔒 |   | |
||||||
| **EIP712** | Implementation |  |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | _domainSeparatorV4 | Internal 🔒 |   | |
| └ | _buildDomainSeparator | Private 🔐 |   | |
| └ | _hashTypedDataV4 | Internal 🔒 |   | |
||||||
| **ERC165** | Implementation | IERC165 |||
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
||||||
| **SafeCast** | Library |  |||
| └ | toUint224 | Internal 🔒 |   | |
| └ | toUint128 | Internal 🔒 |   | |
| └ | toUint96 | Internal 🔒 |   | |
| └ | toUint64 | Internal 🔒 |   | |
| └ | toUint32 | Internal 🔒 |   | |
| └ | toUint16 | Internal 🔒 |   | |
| └ | toUint8 | Internal 🔒 |   | |
| └ | toUint256 | Internal 🔒 |   | |
| └ | toInt128 | Internal 🔒 |   | |
| └ | toInt64 | Internal 🔒 |   | |
| └ | toInt32 | Internal 🔒 |   | |
| └ | toInt16 | Internal 🔒 |   | |
| └ | toInt8 | Internal 🔒 |   | |
| └ | toInt256 | Internal 🔒 |   | |
||||||
| **DoubleEndedQueue** | Library |  |||
| └ | pushBack | Internal 🔒 | 🛑  | |
| └ | popBack | Internal 🔒 | 🛑  | |
| └ | pushFront | Internal 🔒 | 🛑  | |
| └ | popFront | Internal 🔒 | 🛑  | |
| └ | front | Internal 🔒 |   | |
| └ | back | Internal 🔒 |   | |
| └ | at | Internal 🔒 |   | |
| └ | clear | Internal 🔒 | 🛑  | |
| └ | length | Internal 🔒 |   | |
| └ | empty | Internal 🔒 |   | |
||||||
| **Address** | Library |  |||
| └ | isContract | Internal 🔒 |   | |
| └ | sendValue | Internal 🔒 | 🛑  | |
| └ | functionCall | Internal 🔒 | 🛑  | |
| └ | functionCall | Internal 🔒 | 🛑  | |
| └ | functionCallWithValue | Internal 🔒 | 🛑  | |
| └ | functionCallWithValue | Internal 🔒 | 🛑  | |
| └ | functionStaticCall | Internal 🔒 |   | |
| └ | functionStaticCall | Internal 🔒 |   | |
| └ | functionDelegateCall | Internal 🔒 | 🛑  | |
| └ | functionDelegateCall | Internal 🔒 | 🛑  | |
| └ | verifyCallResult | Internal 🔒 |   | |
||||||
| **Context** | Implementation |  |||
| └ | _msgSender | Internal 🔒 |   | |
| └ | _msgData | Internal 🔒 |   | |
||||||
| **Timers** | Library |  |||
| └ | getDeadline | Internal 🔒 |   | |
| └ | setDeadline | Internal 🔒 | 🛑  | |
| └ | reset | Internal 🔒 | 🛑  | |
| └ | isUnset | Internal 🔒 |   | |
| └ | isStarted | Internal 🔒 |   | |
| └ | isPending | Internal 🔒 |   | |
| └ | isExpired | Internal 🔒 |   | |
| └ | getDeadline | Internal 🔒 |   | |
| └ | setDeadline | Internal 🔒 | 🛑  | |
| └ | reset | Internal 🔒 | 🛑  | |
| └ | isUnset | Internal 🔒 |   | |
| └ | isStarted | Internal 🔒 |   | |
| └ | isPending | Internal 🔒 |   | |
| └ | isExpired | Internal 🔒 |   | |
||||||
| **IGovernor** | Implementation | IERC165 |||
| └ | name | Public ❗️ |   |NO❗️ |
| └ | version | Public ❗️ |   |NO❗️ |
| └ | COUNTING_MODE | Public ❗️ |   |NO❗️ |
| └ | hashProposal | Public ❗️ |   |NO❗️ |
| └ | state | Public ❗️ |   |NO❗️ |
| └ | proposalSnapshot | Public ❗️ |   |NO❗️ |
| └ | proposalDeadline | Public ❗️ |   |NO❗️ |
| └ | votingDelay | Public ❗️ |   |NO❗️ |
| └ | votingPeriod | Public ❗️ |   |NO❗️ |
| └ | quorum | Public ❗️ |   |NO❗️ |
| └ | getVotes | Public ❗️ |   |NO❗️ |
| └ | getVotesWithParams | Public ❗️ |   |NO❗️ |
| └ | hasVoted | Public ❗️ |   |NO❗️ |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | execute | Public ❗️ |  💵 |NO❗️ |
| └ | castVote | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReason | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReasonAndParams | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteBySig | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReasonAndParamsBySig | Public ❗️ | 🛑  |NO❗️ |
||||||
| **Governor** | Implementation | Context, ERC165, EIP712, IGovernor, IERC721Receiver, IERC1155Receiver |||
| └ | <Constructor> | Public ❗️ | 🛑  | EIP712 |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | name | Public ❗️ |   |NO❗️ |
| └ | version | Public ❗️ |   |NO❗️ |
| └ | hashProposal | Public ❗️ |   |NO❗️ |
| └ | state | Public ❗️ |   |NO❗️ |
| └ | proposalSnapshot | Public ❗️ |   |NO❗️ |
| └ | proposalDeadline | Public ❗️ |   |NO❗️ |
| └ | proposalThreshold | Public ❗️ |   |NO❗️ |
| └ | _quorumReached | Internal 🔒 |   | |
| └ | _voteSucceeded | Internal 🔒 |   | |
| └ | _getVotes | Internal 🔒 |   | |
| └ | _countVote | Internal 🔒 | 🛑  | |
| └ | _defaultParams | Internal 🔒 |   | |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | execute | Public ❗️ |  💵 |NO❗️ |
| └ | _execute | Internal 🔒 | 🛑  | |
| └ | _beforeExecute | Internal 🔒 | 🛑  | |
| └ | _afterExecute | Internal 🔒 | 🛑  | |
| └ | _cancel | Internal 🔒 | 🛑  | |
| └ | getVotes | Public ❗️ |   |NO❗️ |
| └ | getVotesWithParams | Public ❗️ |   |NO❗️ |
| └ | castVote | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReason | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReasonAndParams | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteBySig | Public ❗️ | 🛑  |NO❗️ |
| └ | castVoteWithReasonAndParamsBySig | Public ❗️ | 🛑  |NO❗️ |
| └ | _castVote | Internal 🔒 | 🛑  | |
| └ | _castVote | Internal 🔒 | 🛑  | |
| └ | relay | External ❗️ | 🛑  | onlyGovernance |
| └ | _executor | Internal 🔒 |   | |
| └ | onERC721Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155BatchReceived | Public ❗️ | 🛑  |NO❗️ |
||||||
| **GovernorSettings** | Implementation | Governor |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | votingDelay | Public ❗️ |   |NO❗️ |
| └ | votingPeriod | Public ❗️ |   |NO❗️ |
| └ | proposalThreshold | Public ❗️ |   |NO❗️ |
| └ | setVotingDelay | Public ❗️ | 🛑  | onlyGovernance |
| └ | setVotingPeriod | Public ❗️ | 🛑  | onlyGovernance |
| └ | setProposalThreshold | Public ❗️ | 🛑  | onlyGovernance |
| └ | _setVotingDelay | Internal 🔒 | 🛑  | |
| └ | _setVotingPeriod | Internal 🔒 | 🛑  | |
| └ | _setProposalThreshold | Internal 🔒 | 🛑  | |
||||||
| **Counters** | Library |  |||
| └ | current | Internal 🔒 |   | |
| └ | increment | Internal 🔒 | 🛑  | |
| └ | decrement | Internal 🔒 | 🛑  | |
| └ | reset | Internal 🔒 | 🛑  | |
||||||
| **IGovernorTimelock** | Implementation | IGovernor |||
| └ | timelock | Public ❗️ |   |NO❗️ |
| └ | proposalEta | Public ❗️ |   |NO❗️ |
| └ | queue | Public ❗️ | 🛑  |NO❗️ |
||||||
| **IGovernorCompatibilityBravo** | Implementation | IGovernor |||
| └ | quorumVotes | Public ❗️ |   |NO❗️ |
| └ | proposals | Public ❗️ |   |NO❗️ |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | queue | Public ❗️ | 🛑  |NO❗️ |
| └ | execute | Public ❗️ |  💵 |NO❗️ |
| └ | cancel | Public ❗️ | 🛑  |NO❗️ |
| └ | getActions | Public ❗️ |   |NO❗️ |
| └ | getReceipt | Public ❗️ |   |NO❗️ |
||||||
| **GovernorCompatibilityBravo** | Implementation | IGovernorTimelock, IGovernorCompatibilityBravo, Governor |||
| └ | COUNTING_MODE | Public ❗️ |   |NO❗️ |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | queue | Public ❗️ | 🛑  |NO❗️ |
| └ | execute | Public ❗️ |  💵 |NO❗️ |
| └ | cancel | Public ❗️ | 🛑  |NO❗️ |
| └ | _encodeCalldata | Private 🔐 |   | |
| └ | _storeProposal | Private 🔐 | 🛑  | |
| └ | proposals | Public ❗️ |   |NO❗️ |
| └ | getActions | Public ❗️ |   |NO❗️ |
| └ | getReceipt | Public ❗️ |   |NO❗️ |
| └ | quorumVotes | Public ❗️ |   |NO❗️ |
| └ | hasVoted | Public ❗️ |   |NO❗️ |
| └ | _quorumReached | Internal 🔒 |   | |
| └ | _voteSucceeded | Internal 🔒 |   | |
| └ | _countVote | Internal 🔒 | 🛑  | |
||||||
| **IVotes** | Interface |  |||
| └ | getVotes | External ❗️ |   |NO❗️ |
| └ | getPastVotes | External ❗️ |   |NO❗️ |
| └ | getPastTotalSupply | External ❗️ |   |NO❗️ |
| └ | delegates | External ❗️ |   |NO❗️ |
| └ | delegate | External ❗️ | 🛑  |NO❗️ |
| └ | delegateBySig | External ❗️ | 🛑  |NO❗️ |
||||||
| **GovernorVotes** | Implementation | Governor |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | _getVotes | Internal 🔒 |   | |
||||||
| **GovernorVotesQuorumFraction** | Implementation | GovernorVotes |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | quorumNumerator | Public ❗️ |   |NO❗️ |
| └ | quorumDenominator | Public ❗️ |   |NO❗️ |
| └ | quorum | Public ❗️ |   |NO❗️ |
| └ | updateQuorumNumerator | External ❗️ | 🛑  | onlyGovernance |
| └ | _updateQuorumNumerator | Internal 🔒 | 🛑  | |
||||||
| **IAccessControl** | Interface |  |||
| └ | hasRole | External ❗️ |   |NO❗️ |
| └ | getRoleAdmin | External ❗️ |   |NO❗️ |
| └ | grantRole | External ❗️ | 🛑  |NO❗️ |
| └ | revokeRole | External ❗️ | 🛑  |NO❗️ |
| └ | renounceRole | External ❗️ | 🛑  |NO❗️ |
||||||
| **AccessControl** | Implementation | Context, IAccessControl, ERC165 |||
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | hasRole | Public ❗️ |   |NO❗️ |
| └ | _checkRole | Internal 🔒 |   | |
| └ | _checkRole | Internal 🔒 |   | |
| └ | getRoleAdmin | Public ❗️ |   |NO❗️ |
| └ | grantRole | Public ❗️ | 🛑  | onlyRole |
| └ | revokeRole | Public ❗️ | 🛑  | onlyRole |
| └ | renounceRole | Public ❗️ | 🛑  |NO❗️ |
| └ | _setupRole | Internal 🔒 | 🛑  | |
| └ | _setRoleAdmin | Internal 🔒 | 🛑  | |
| └ | _grantRole | Internal 🔒 | 🛑  | |
| └ | _revokeRole | Internal 🔒 | 🛑  | |
||||||
| **TimelockController** | Implementation | AccessControl, IERC721Receiver, IERC1155Receiver |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | isOperation | Public ❗️ |   |NO❗️ |
| └ | isOperationPending | Public ❗️ |   |NO❗️ |
| └ | isOperationReady | Public ❗️ |   |NO❗️ |
| └ | isOperationDone | Public ❗️ |   |NO❗️ |
| └ | getTimestamp | Public ❗️ |   |NO❗️ |
| └ | getMinDelay | Public ❗️ |   |NO❗️ |
| └ | hashOperation | Public ❗️ |   |NO❗️ |
| └ | hashOperationBatch | Public ❗️ |   |NO❗️ |
| └ | schedule | Public ❗️ | 🛑  | onlyRole |
| └ | scheduleBatch | Public ❗️ | 🛑  | onlyRole |
| └ | _schedule | Private 🔐 | 🛑  | |
| └ | cancel | Public ❗️ | 🛑  | onlyRole |
| └ | execute | Public ❗️ |  💵 | onlyRoleOrOpenRole |
| └ | executeBatch | Public ❗️ |  💵 | onlyRoleOrOpenRole |
| └ | _beforeCall | Private 🔐 |   | |
| └ | _afterCall | Private 🔐 | 🛑  | |
| └ | _call | Private 🔐 | 🛑  | |
| └ | updateDelay | External ❗️ | 🛑  |NO❗️ |
| └ | onERC721Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155Received | Public ❗️ | 🛑  |NO❗️ |
| └ | onERC1155BatchReceived | Public ❗️ | 🛑  |NO❗️ |
||||||
| **GovernorTimelockControl** | Implementation | IGovernorTimelock, Governor |||
| └ | <Constructor> | Public ❗️ | 🛑  |NO❗️ |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |
| └ | state | Public ❗️ |   |NO❗️ |
| └ | timelock | Public ❗️ |   |NO❗️ |
| └ | proposalEta | Public ❗️ |   |NO❗️ |
| └ | queue | Public ❗️ | 🛑  |NO❗️ |
| └ | _execute | Internal 🔒 | 🛑  | |
| └ | _cancel | Internal 🔒 | 🛑  | |
| └ | _executor | Internal 🔒 |   | |
| └ | updateTimelock | External ❗️ | 🛑  | onlyGovernance |
| └ | _updateTimelock | Private 🔐 | 🛑  | |
||||||
| **GovernorOLA** | Implementation | Governor, GovernorSettings, GovernorCompatibilityBravo, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl |||
| └ | <Constructor> | Public ❗️ | 🛑  | Governor GovernorSettings GovernorVotes GovernorVotesQuorumFraction GovernorTimelockControl |
| └ | state | Public ❗️ |   |NO❗️ |
| └ | propose | Public ❗️ | 🛑  |NO❗️ |
| └ | proposalThreshold | Public ❗️ |   |NO❗️ |
| └ | _execute | Internal 🔒 | 🛑  | |
| └ | _cancel | Internal 🔒 | 🛑  | |
| └ | _executor | Internal 🔒 |   | |
| └ | supportsInterface | Public ❗️ |   |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
