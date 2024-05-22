module.exports = {
    skipFiles: ["bridges/test/FxChildTunnel.sol",
        "bridges/test/ChildMockERC20.sol",
        "bridges/test/FxRootMock.sol",
        "bridges/test/HomeMediatorTest.sol",
        "bridges/test/MockAMBMediator.sol",
        "bridges/test/MockL2Relayer.sol",
        "bridges/test/MockTimelock.sol",
        "bridges/test/WormholeL1Receiver.sol",
        "bridges/test/WormholeL1Sender.sol",
        "bridges/test/WormholeL2ReceiverL1Sender.sol",
        "multisigs/test/DelegatecallExploit.sol",
        "multisigs/test/MockTimelockCM.sol",
        "multisigs/test/MockTreasury.sol",
        "test/BridgeSetup.sol",
        "test/BrokenERC20.sol",
        "test/EchidnaVoteWeightingAssert.sol",
        "test/SafeSetup.sol",
        "test/VoteWeightingFuzzing.sol"
    ]
};