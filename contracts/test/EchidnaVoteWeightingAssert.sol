// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../OLAS.sol";
import "../veOLAS.sol";
import "./VoteWeightingFuzzing.sol";


contract EchidnaVoteWeightingAssert {    
    OLAS olas;
    veOLAS ve;
    VoteWeightingFuzzing vw;

    uint256 constant oneOLASBalance = 1 ether;
    uint256 constant fourYear = 4 * 365 * 86400;
    uint256 constant oneYear = 1 * 365 * 86400;
    uint256 constant maxVoteWeight = 10000;
    uint64  constant WEEK = 1 weeks;
    uint256 constant oneOLAS = 1 ether;
    uint256 constant oneMLN = 1_000_000;
    uint256 ts;
    
    // msg.sender in Echidna 
    address[3] private senders = [ address(0x10000), address(0x20000), address(0x30000) ];

    constructor() payable {
        olas = new OLAS();
        address aolas = address(olas);
        ve = new veOLAS(aolas, "Voting Escrow OLAS", "veOLAS");
        address ave = address(ve); 
        vw = new VoteWeightingFuzzing(ave);
        olas.mint(address(this),oneOLAS*oneMLN);
    }

    // voteForNomineeWeights_assert(0xdeadbeef,1,0,4495678220902361,1124857)
    function voteForNomineeWeights_assert(address account, uint32 chainId, uint16 weight, uint256 amount, uint32 unlockTime) external {
        require(block.timestamp > 0);
        require(block.timestamp > ts);
        require(unlockTime < fourYear);
        require(weight < maxVoteWeight);
        require(amount < 100 * oneOLAS);
        uint256 balanceOf = olas.balanceOf(address(this));
        assert(balanceOf > amount);
        (uint128 initialAmount,) = ve.mapLockedBalances(address(this));
        if (initialAmount == 0) {
            olas.approve(address(ve), amount);
            ve.createLock(amount, unlockTime);
            (uint128 lockedAmount,) = ve.mapLockedBalances(address(this));
            assert(lockedAmount > 0);
        } else {
            (uint128 lockedAmount,) = ve.mapLockedBalances(address(this));
            assert(lockedAmount > 0);
        }
        vw.addNomineeEVM(account, chainId);
        bytes32 nominee = bytes32(uint256(uint160(account)));
        uint256 id = vw.getNomineeId(nominee, chainId);
        uint256 num = vw.getNumNominees();
        assert(id > 0);
        assert(num > 0);
        vw.setCallVoteForNomineeWeights(false);
        bool beforeAfterCall = vw.callVoteForNomineeWeights();
        assert(beforeAfterCall == false);
        vw.voteForNomineeWeights(nominee, chainId, weight);
        bool stateAfterCall = vw.callVoteForNomineeWeights();
        if(stateAfterCall == true) {
            uint256 lts = vw.getlastUserVote(nominee,chainId);
            assert(lts > 0);
        }
        ts = block.timestamp; // next timestamp > timestamp
        vw.checkpointNominee(nominee, chainId);
    }

}

