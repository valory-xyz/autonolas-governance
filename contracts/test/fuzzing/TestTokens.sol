// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {OLASFuzzing} from "./OLASFuzzing.sol";
import {veOLASFuzzing} from "./veOLASFuzzing.sol";
import {buOLASFuzzing} from "./buOLASFuzzing.sol";

contract TestTokenomics {
    OLASFuzzing public olas;
    veOLASFuzzing public ve;
    buOLASFuzzing public bu;

    uint256 internal lastTime;
    uint256[] internal emptyArray;
    uint256 internal initialMint = 100_000_000e18;
    uint256 internal WEEK = 1 weeks;
    bool internal initialized;

    constructor(address _olas, address _ve, address _bu) payable
    {
        emptyArray = new uint256[](0);

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

        // Set the initial timestamp
        lastTime = block.timestamp;
    }


    /// @dev Mint OLAS tokens.
    function mint(uint256 amount) external {
        olas.mint(address(this), amount);
    }

    /// @dev Burn OLAS tokens.
    function burn(uint256 amount) external {
        olas.burn(amount);
    }

    /// @dev Checkpoint in veOLAS.
    function checkpointVE() external {
        require(block.timestamp > lastTime);
        ve.checkpoint();
        lastTime = block.timestamp;
    }

    /// @dev depositFor in veOLAS.
    function depositForVE(address account, uint256 amount) external {
        require(block.timestamp > lastTime);
        ve.depositFor(account, amount);
        lastTime = block.timestamp;
    }

    /// @dev createLock in veOLAS.
    function createLockVE(uint256 amount, uint256 unlockTime) external {
        require(block.timestamp > lastTime);
        ve.createLock(amount, unlockTime);
        lastTime = block.timestamp;
    }

    /// @dev createLockFor in veOLAS.
    function createLockForVE(address account, uint256 amount, uint256 unlockTime) external {
        require(block.timestamp > lastTime);
        ve.createLockFor(account, amount, unlockTime);
        lastTime = block.timestamp;
    }

    /// @dev increaseAmount in veOLAS.
    function increaseAmountVE(uint256 amount) external {
        require(block.timestamp > lastTime);
        ve.increaseAmount(amount);
        lastTime = block.timestamp;
    }

    /// @dev increaseAmount in veOLAS.
    function increaseUnlockTimeVE(uint256 unlockTime) external {
        require(block.timestamp > lastTime);
        ve.increaseUnlockTime(unlockTime);
        lastTime = block.timestamp;
    }

    /// @dev withdraw in veOLAS.
    function withdrawVE() external {
        require(block.timestamp > lastTime);
        ve.withdraw();
        lastTime = block.timestamp;
    }

    /// @dev createLockFor in buOLAS.
    function createLockForBU(address account, uint256 amount, uint256 numSteps) external {
        require(block.timestamp > lastTime);
        bu.createLockFor(account, amount, numSteps);
        lastTime = block.timestamp;
    }

    /// @dev withdraw in buOLAS.
    function withdrawBU() external {
        require(block.timestamp > lastTime);
        bu.withdraw();
        lastTime = block.timestamp;
    }

    /// @dev revoke in buOLAS.
    function revokeBU(address[] memory accounts) external {
        require(block.timestamp > lastTime);
        bu.revoke(accounts);
        lastTime = block.timestamp;
    }
}
