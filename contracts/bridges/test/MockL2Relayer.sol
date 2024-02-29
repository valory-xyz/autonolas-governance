// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBridgeMessenger {
    function processMessageFromForeign(bytes memory data) external;
    function processMessageFromSource(bytes memory data) external;
    function receiveWormholeMessages(
        bytes memory data,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external;
}

/// @title MockL2Relayer - Smart contract for mocking the L2 relayer contract
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract MockL2Relayer {
    address public homeMediator;
    address public foreignGovernor;

    uint16 public sourceChain = 2; // ETH
    bytes32 public constant DELIVERY_HASH = 0;

    constructor(address _homeMediator, address _foreignGovernor) {
        homeMediator = _homeMediator;
        foreignGovernor = _foreignGovernor;
    }

    function changeBridgeMessenger(address _homeMediator) external {
        homeMediator = _homeMediator;
    }

    function changeForeignGovernor(address _foreignGovernor) external {
        foreignGovernor = _foreignGovernor;
    }

    function changeSourceGovernor(address _foreignGovernor) external {
        foreignGovernor = _foreignGovernor;
    }

    function messageSender() external view returns (address) {
        return foreignGovernor;
    }

    function xDomainMessageSender() external view returns (address) {
        return foreignGovernor;
    }

    function processMessageFromForeign(bytes memory data) public {
        IBridgeMessenger(homeMediator).processMessageFromForeign(data);
    }

    function processMessageFromSource(bytes memory data) external {
        IBridgeMessenger(homeMediator).processMessageFromSource(data);
    }
    
    function changeSourceChain(uint16 chainId) external {
        sourceChain = chainId;
    }

    function receiveWormholeMessages(bytes memory data) external {
        bytes32 sourceAddress = bytes32(uint256(uint160(foreignGovernor)));
        IBridgeMessenger(homeMediator).receiveWormholeMessages(data, new bytes[](0), sourceAddress, sourceChain, DELIVERY_HASH);
    }
}