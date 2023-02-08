// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {OLASFuzzing} from "./OLASFuzzing.sol";
import {veOLASFuzzing} from "./veOLASFuzzing.sol";
import {buOLASFuzzing} from "./buOLASFuzzing.sol";

contract TestTokens {
    OLASFuzzing public olas;
    veOLASFuzzing public ve;
    buOLASFuzzing public bu;

    uint256 internal lastTime;
    uint256 internal lastBlock;
    uint256 internal initialMint = 100_000_000 ether;
    bool internal initialized;

    constructor(address _olas, address _ve, address _bu) payable
    {
        olas = OLASFuzzing(_olas);
        ve = veOLASFuzzing(_ve);
        bu = buOLASFuzzing(_bu);
    }

    receive() external payable {
    }

    function setUp() external {
        if (initialized) {
            revert();
        }
        initialized = true;
        olas.changeMinter(address(this));
        olas.mint(address(this), initialMint);
        olas.mint(0xAaaaAaAAaaaAAaAAaAaaaaAAAAAaAaaaAaAaaAA0, initialMint);
        olas.mint(0xAaAaaAAAaAaaAaAaAaaAAaAaAAAAAaAAAaaAaAa2, initialMint);

        // Approve for veOLAS and buOLAS
        olas.approve(address(ve), type(uint256).max);
        olas.approve(address(bu), type(uint256).max);

        ve.createLockFor(0xAaaaAaAAaaaAAaAAaAaaaaAAAAAaAaaaAaAaaAA0, 1000 ether, 1 weeks);
        bu.createLockFor(0xAaaaAaAAaaaAAaAAaAaaaaAAAAAaAaaaAaAaaAA0, 1000 ether, 1);
        ve.createLockFor(0xAaAaaAAAaAaaAaAaAaaAAaAaAAAAAaAAAaaAaAa2, 10_000 ether, 60 weeks);
        bu.createLockFor(0xAaAaaAAAaAaaAaAaAaaAAaAaAAAAAaAAAaaAaAa2, 10_000 ether, 2);
        ve.createLock(100_000 ether, 200 weeks);
        bu.createLockFor(address(this), 100_000 ether, 4);

        // Set the initial timestamp
        lastTime = block.timestamp;
    }


    /// @dev Mint OLAS tokens.
    function mint(uint256 amount) external {
        olas.mint(address(this), amount);
    }

    /// @dev Burn OLAS tokens.
    function burn(uint256 amount) external {
        require(olas.balanceOf(address(this)) >= amount);
        olas.burn(amount);
    }

    /// @dev Checkpoint in veOLAS.
    function checkpointVE() external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.checkpoint();
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev depositFor in veOLAS.
    function depositForVE(address account, uint256 amount) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.depositFor(account, amount);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev createLock in veOLAS.
    function createLockVE(uint256 amount, uint256 unlockTime) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.createLock(amount, unlockTime);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev createLockFor in veOLAS.
    function createLockForVE(address account, uint256 amount, uint256 unlockTime) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.createLockFor(account, amount, unlockTime);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev increaseAmount in veOLAS.
    function increaseAmountVE(uint256 amount) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.increaseAmount(amount);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev increaseAmount in veOLAS.
    function increaseUnlockTimeVE(uint256 unlockTime) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.increaseUnlockTime(unlockTime);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev withdraw in veOLAS.
    function withdrawVE() external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        ve.withdraw();
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev createLockFor in buOLAS.
    function createLockForBU(address account, uint256 amount, uint256 numSteps) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        bu.createLockFor(account, amount, numSteps);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev withdraw in buOLAS.
    function withdrawBU() external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        bu.withdraw();
        lastTime = block.timestamp;
        lastBlock = block.number;
    }

    /// @dev revoke in buOLAS.
    function revokeBU(address[] memory accounts) external {
        require(block.timestamp >= lastTime && block.number >= lastBlock);
        bu.revoke(accounts);
        lastTime = block.timestamp;
        lastBlock = block.number;
    }
}
