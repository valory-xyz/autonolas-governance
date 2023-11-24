// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IFxERC20ChildTunnel {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes calldata data) external;
}

/// @title FxRootMock - Root mock contract for fx-portal
contract FxRootMock {
    address public fxERC20RootTunnel;

    function setRootTunnel(address _fxERC20RootTunnel) external {
        fxERC20RootTunnel = _fxERC20RootTunnel;
    }

    /// @dev Mock of the send message to child.
    /// @param _receiver FxERC20RootTunnel contract address.
    /// @param _data Message to send to L2.
    function sendMessageToChild(address _receiver, bytes calldata _data) external {
        IFxERC20ChildTunnel(_receiver).processMessageFromRoot(0, fxERC20RootTunnel, _data);
    }
}
