// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHomeMediator {
    function processMessageFromForeign(bytes memory data) external;
}

/// @title MockAMBMediator - Smart contract for mocking the AMBMediator contract on the Gnosis chain
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockAMBMediator {
    address public homeMediator;
    address public foreignGovernor;

    constructor(address _homeMediator, address _foreignGovernor) {
        homeMediator = _homeMediator;
        foreignGovernor = _foreignGovernor;
    }

    function changeHomeMediator(address _homeMediator) external {
        homeMediator = _homeMediator;
    }

    function changeForeignGovernor(address _foreignGovernor) external {
        foreignGovernor = _foreignGovernor;
    }

    function messageSender() external view returns (address) {
        return foreignGovernor;
    }

    function processMessageFromForeign(bytes memory data) external {
        IHomeMediator(homeMediator).processMessageFromForeign(data);
    }
}