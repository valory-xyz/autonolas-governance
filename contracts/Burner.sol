// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Burns tokens.
    /// @param amount Token amount to burn.
    function burn(uint256 amount) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided value provided.
error ZeroValue();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title Burner - Smart contract for burning OLAS token.
contract Burner {
    event Burned(uint256 amount);

    // OLAS address
    address public immutable olas;
    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev Burner constructor.
    /// @param _olas OLAS address.
    constructor(address _olas) {
        if (_olas == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
    }

    /// @dev Burns OLAS tokens owned by this contract.
    function burn() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get OLAS balance
        uint256 olasBalance = IToken(olas).balanceOf(address(this));

        // Check for zero value
        if (olasBalance == 0) {
            revert ZeroValue();
        }

        // Burn tokens
        IToken(olas).burn(olasBalance);

        emit Burned(olasBalance);

        _locked = 1;
    }
}
