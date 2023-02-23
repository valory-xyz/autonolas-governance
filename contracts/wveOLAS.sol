// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Structure for veOLAS points
struct PointVoting {
    int128 bias;
    int128 slope;
    uint64 ts;
    uint64 blockNumber;
    uint128 balance;
}

interface IVEOLAS {
    /// @dev Gets the total number of supply points.
    /// @return numPoints Number of supply points.
    function totalNumPoints() external view returns (uint256 numPoints);

    /// @dev Gets the supply point of a specified index.
    /// @param idx Supply point number.
    /// @return sPoint Supply point.
    function mapSupplyPoints(uint256 idx) external view returns (PointVoting memory sPoint);

    /// @dev Gets the number of user points.
    /// @param account Account address.
    /// @return userNumPoints Number of user points.
    function getNumUserPoints(address account) external view returns (uint256 userNumPoints);

    /// @dev Gets the checkpoint structure at number `idx` for `account`.
    /// @notice The out of bound condition is treated by the default code generation check.
    /// @param account User wallet address.
    /// @param idx User point number.
    /// @return uPoint The requested user point.
    function getUserPoint(address account, uint256 idx) external view returns (PointVoting memory uPoint);

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256 balance);

    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Account balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance);

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt);

    /// @dev Calculates total voting power at time `ts`.
    /// @param ts Time to get total voting power at.
    /// @return vPower Total voting power.
    function totalSupplyLockedAtT(uint256 ts) external view returns (uint256 vPower);

    /// @dev Calculate total voting power at some point in the past.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return vPower Total voting power.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256 vPower);
}

/// @dev Zero veOLAS address.
error ZeroVEOLASAddress();

/// @dev Provided wrong timestamp.
/// @param minTimeStamp Minimum timestamp.
/// @param providedTimeStamp Provided timestamp.
error WrongTimestamp(uint256 minTimeStamp, uint256 providedTimeStamp);

/// @dev Called function is implemented in a specified veOLAS contract.
/// @param ve Original veOLAS address.
error ImplementedIn(address ve);

/// @title wveOLAS - Wrapper smart contract for view functions of veOLAS contract
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract wveOLAS {
    // veOLAS address
    address public immutable ve;

    /// @dev TokenomicsProxy constructor.
    /// @param _ve veOLAS address.
    constructor(address _ve) {
        // Check for the zero address
        if (_ve == address(0)) {
            revert ZeroVEOLASAddress();
        }
        ve = _ve;
    }

    /// @dev Gets the checkpoint structure at number `idx` for `account`.
    /// @notice The out of bound condition is treated by the default code generation check.
    /// @param account User wallet address.
    /// @param idx User point number.
    /// @return uPoint The requested user point.
    function getUserPoint(address account, uint256 idx) public view returns (PointVoting memory uPoint) {
        // Get the number of user points
        uint256 userNumPoints = IVEOLAS(ve).getNumUserPoints(account);
        if (userNumPoints > 0) {
            uPoint = IVEOLAS(ve).getUserPoint(account, idx);
        }
    }

    /// @dev Gets voting power at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Voting balance / power.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256 balance) {
        // Get the zero account point
        PointVoting memory uPoint = getUserPoint(account, 0);
        // Check that the point exists and the zero point block number is not smaller than the specified blockNumber
        if (uPoint.blockNumber > 0 && blockNumber >= uPoint.blockNumber) {
            balance = IVEOLAS(ve).getPastVotes(account, blockNumber);
        }
    }

    /// @dev Gets the account balance at a specific block number.
    /// @param account Account address.
    /// @param blockNumber Block number.
    /// @return balance Account balance.
    function balanceOfAt(address account, uint256 blockNumber) external view returns (uint256 balance) {
        // Get the zero account point
        PointVoting memory uPoint = getUserPoint(account, 0);
        // Check that the zero point block number is not smaller than the specified blockNumber
        if (blockNumber >= uPoint.blockNumber) {
            balance = IVEOLAS(ve).balanceOfAt(account, blockNumber);
        }
    }

    /// @dev Gets total token supply at a specific block number.
    /// @param blockNumber Block number.
    /// @return supplyAt Supply at the specified block number.
    function totalSupplyAt(uint256 blockNumber) external view returns (uint256 supplyAt) {
        supplyAt = IVEOLAS(ve).totalSupplyAt(blockNumber);
    }

    /// @dev Calculates total voting power at time `ts` that must be greater than the last supply point timestamp.
    /// @param ts Time to get total voting power at.
    /// @return vPower Total voting power.
    function totalSupplyLockedAtT(uint256 ts) external view returns (uint256 vPower) {
        // Get the total number of supply points
        uint256 numPoints = IVEOLAS(ve).totalNumPoints();
        PointVoting memory sPoint = IVEOLAS(ve).mapSupplyPoints(numPoints);
        // Check the last supply point timestamp is not smaller than the specified ts
        if (ts >= sPoint.ts) {
            vPower = IVEOLAS(ve).totalSupplyLockedAtT(ts);
        } else {
            revert WrongTimestamp(sPoint.ts, ts);
        }
    }

    /// @dev Calculate total voting power at some point in the past.
    /// @notice The requested block number must be at least equal to the zero supply point block number.
    /// @param blockNumber Block number to calculate the total voting power at.
    /// @return vPower Total voting power.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256 vPower) {
        // Get the zero supply point
        PointVoting memory sPoint = IVEOLAS(ve).mapSupplyPoints(0);
        // Check the requested block number to be at least equal to the zero supply point block number
        if (blockNumber >= sPoint.blockNumber) {
            vPower = IVEOLAS(ve).getPastTotalSupply(blockNumber);
        }
    }

    /// @dev Reverts other calls such that the original veOLAS is used.
    fallback() external {
        revert ImplementedIn(ve);
    }
}
