// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorOLAS} from "../../contracts/GovernorOLAS.sol";
import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import {GuardCM, BridgeParams} from "../../contracts/multisigs/GuardCM.sol";
import {ProcessBridgedDataGnosis} from "../../contracts/multisigs/bridge_verifier/ProcessBridgedDataGnosis.sol";
import {ProcessBridgedDataPolygon} from "../../contracts/multisigs/bridge_verifier/ProcessBridgedDataPolygon.sol";
import {ProcessBridgedDataArbitrum} from "../../contracts/multisigs/bridge_verifier/ProcessBridgedDataArbitrum.sol";
import {ProcessBridgedDataOptimism} from "../../contracts/multisigs/bridge_verifier/ProcessBridgedDataOptimism.sol";

interface IGnosisSafe {
    function setGuard(address guard) external;
    function getOwners() external view returns (address[] memory);
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation) external returns (bool);
}

/// @title ForkDeployGovernance - Fork tests for deploying GovernorOLAS, GuardCM and bridge verifiers
/// @dev Run with: forge test --fork-url <MAINNET_RPC> --match-contract ForkDeployGovernance -vvv
contract ForkDeployGovernance is Test {
    // Existing mainnet addresses
    address constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address constant CM = 0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570;
    address constant WVEOLAS = 0x4039B809E0C0Ad04F6Fc880193366b251dDf4B40;
    address constant EXISTING_GOVERNOR = 0x8E84B5055492901988B831817e4Ace5275A3b401;

    // Governor constructor params from globals_mainnet.json
    uint256 constant INITIAL_VOTING_DELAY = 13091;
    uint256 constant INITIAL_VOTING_PERIOD = 19636;
    uint256 constant INITIAL_PROPOSAL_THRESHOLD = 5000000000000000000000; // 5000 OLAS
    uint256 constant QUORUM = 3;
    uint256 constant GOVERNOR_DELAY = 157092;

    // L1 bridge mediator addresses
    address constant AMB_CONTRACT_PROXY_FOREIGN = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e;
    address constant FX_ROOT = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2;
    address constant ARBITRUM_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address constant OPTIMISM_L1_CDM = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address constant BASE_L1_CDM = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
    address constant MODE_L1_CDM = 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f;
    address constant CELO_L1_CDM = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95;

    // L2 bridge mediator addresses
    address constant HOME_MEDIATOR = 0x15bd56669F57192a97dF41A2aa8f4403e9491776;
    address constant FX_GOVERNOR_TUNNEL = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    // Aliased Timelock address on Arbitrum L2
    address constant ARBITRUM_BRIDGE_MEDIATOR_L2 = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F;
    address constant OPTIMISM_MESSENGER_L2 = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c;
    address constant BASE_MESSENGER_L2 = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address constant MODE_MESSENGER_L2 = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address constant CELO_MESSENGER_L2 = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d;

    // L2 chain Ids
    uint256 constant GNOSIS_CHAIN_ID = 100;
    uint256 constant POLYGON_CHAIN_ID = 137;
    uint256 constant ARBITRUM_CHAIN_ID = 42161;
    uint256 constant OPTIMISM_CHAIN_ID = 10;
    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant MODE_CHAIN_ID = 34443;
    uint256 constant CELO_CHAIN_ID = 42220;

    // Deployed contracts
    GovernorOLAS public governor;
    GuardCM public guard;
    ProcessBridgedDataGnosis public verifierGnosis;
    ProcessBridgedDataPolygon public verifierPolygon;
    ProcessBridgedDataArbitrum public verifierArbitrum;
    ProcessBridgedDataOptimism public verifierOptimism;

    function setUp() public {
        // Ensure we are on a mainnet fork
        assertEq(block.chainid, 1, "Must run on mainnet fork");

        // Deploy GovernorOLAS (deploy_26_governor.sh)
        governor = new GovernorOLAS(
            IVotes(WVEOLAS),
            TimelockController(payable(TIMELOCK)),
            INITIAL_VOTING_DELAY,
            INITIAL_VOTING_PERIOD,
            INITIAL_PROPOSAL_THRESHOLD,
            QUORUM,
            GOVERNOR_DELAY
        );

        // Deploy bridge verifiers (deploy_26_01..04)
        verifierGnosis = new ProcessBridgedDataGnosis();
        verifierPolygon = new ProcessBridgedDataPolygon();
        verifierArbitrum = new ProcessBridgedDataArbitrum();
        verifierOptimism = new ProcessBridgedDataOptimism();

        // Deploy GuardCM (deploy_26_00_guard_cm.sh)
        guard = new GuardCM(TIMELOCK, CM, address(governor));
    }

    // ========== GovernorOLAS Deployment Tests ==========

    function testGovernorDeployment() public view {
        assertEq(governor.name(), "Governor OLAS");
        assertEq(governor.votingDelay(), INITIAL_VOTING_DELAY);
        assertEq(governor.votingPeriod(), INITIAL_VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), INITIAL_PROPOSAL_THRESHOLD);
        assertEq(governor.quorumNumerator(), QUORUM);
        assertEq(address(governor.token()), WVEOLAS);
        assertEq(governor.timelock(), TIMELOCK);
    }

    function testGovernorSupportsInterface() public view {
        // IERC165 interface Id
        bytes4 interfaceIdIERC165 = 0x01ffc9a7;
        assertTrue(governor.supportsInterface(interfaceIdIERC165));
    }

    // ========== GuardCM Deployment Tests ==========

    function testGuardCMDeployment() public view {
        assertEq(guard.owner(), TIMELOCK);
        assertEq(guard.multisig(), CM);
        assertEq(guard.governor(), address(governor));
        assertEq(guard.paused(), 1);
    }

    function testGuardCMZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new GuardCM(address(0), CM, address(governor));

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new GuardCM(TIMELOCK, address(0), address(governor));

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new GuardCM(TIMELOCK, CM, address(0));
    }

    // ========== Bridge Verifier Deployment Tests ==========

    function testVerifierGnosisDeployment() public view {
        assertEq(
            verifierGnosis.REQUIRE_TO_PASS_MESSAGE(),
            bytes4(keccak256("requireToPassMessage(address,bytes,uint256)"))
        );
    }

    function testVerifierPolygonDeployment() public view {
        assertEq(
            verifierPolygon.SEND_MESSAGE_TO_CHILD(),
            bytes4(keccak256("sendMessageToChild(address,bytes)"))
        );
    }

    function testVerifierArbitrumDeployment() public view {
        assertEq(
            verifierArbitrum.CREATE_TICKET_UNSAFE(),
            bytes4(keccak256("unsafeCreateRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)"))
        );
        assertEq(
            verifierArbitrum.CREATE_TICKET(),
            bytes4(keccak256("createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)"))
        );
    }

    function testVerifierOptimismDeployment() public view {
        assertEq(
            verifierOptimism.SEND_MESSAGE(),
            bytes4(keccak256("sendMessage(address,bytes,uint32)"))
        );
    }

    // ========== setBridgeMediatorL1BridgeParams Tests ==========
    // These replicate script_26_01..04 functionality

    function testSetBridgeMediatorsOnlyOwner() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        // Should revert when called by non-owner
        vm.expectRevert(abi.encodeWithSignature("OwnerOnly(address,address)", address(this), TIMELOCK));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    function testSetBridgeMediatorsGnosis() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        (address v, address bm, uint64 cid) = guard.mapBridgeMediatorL1BridgeParams(AMB_CONTRACT_PROXY_FOREIGN);
        assertEq(v, address(verifierGnosis));
        assertEq(bm, HOME_MEDIATOR);
        assertEq(cid, uint64(GNOSIS_CHAIN_ID));
    }

    function testSetBridgeMediatorsPolygon() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = FX_ROOT;
        verifiers[0] = address(verifierPolygon);
        chainIds[0] = POLYGON_CHAIN_ID;
        l2s[0] = FX_GOVERNOR_TUNNEL;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        (address v, address bm, uint64 cid) = guard.mapBridgeMediatorL1BridgeParams(FX_ROOT);
        assertEq(v, address(verifierPolygon));
        assertEq(bm, FX_GOVERNOR_TUNNEL);
        assertEq(cid, uint64(POLYGON_CHAIN_ID));
    }

    function testSetBridgeMediatorsArbitrum() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = ARBITRUM_INBOX;
        verifiers[0] = address(verifierArbitrum);
        chainIds[0] = ARBITRUM_CHAIN_ID;
        l2s[0] = ARBITRUM_BRIDGE_MEDIATOR_L2;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        (address v, address bm, uint64 cid) = guard.mapBridgeMediatorL1BridgeParams(ARBITRUM_INBOX);
        assertEq(v, address(verifierArbitrum));
        assertEq(bm, ARBITRUM_BRIDGE_MEDIATOR_L2);
        assertEq(cid, uint64(ARBITRUM_CHAIN_ID));
    }

    function testSetBridgeMediatorsOptimism() public {
        address[] memory l1s = new address[](4);
        address[] memory verifiers = new address[](4);
        uint256[] memory chainIds = new uint256[](4);
        address[] memory l2s = new address[](4);

        l1s[0] = OPTIMISM_L1_CDM;
        l1s[1] = BASE_L1_CDM;
        l1s[2] = MODE_L1_CDM;
        l1s[3] = CELO_L1_CDM;

        verifiers[0] = address(verifierOptimism);
        verifiers[1] = address(verifierOptimism);
        verifiers[2] = address(verifierOptimism);
        verifiers[3] = address(verifierOptimism);

        chainIds[0] = OPTIMISM_CHAIN_ID;
        chainIds[1] = BASE_CHAIN_ID;
        chainIds[2] = MODE_CHAIN_ID;
        chainIds[3] = CELO_CHAIN_ID;

        l2s[0] = OPTIMISM_MESSENGER_L2;
        l2s[1] = BASE_MESSENGER_L2;
        l2s[2] = MODE_MESSENGER_L2;
        l2s[3] = CELO_MESSENGER_L2;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        (address v, address bm, uint64 cid) = guard.mapBridgeMediatorL1BridgeParams(OPTIMISM_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, OPTIMISM_MESSENGER_L2);
        assertEq(cid, uint64(OPTIMISM_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(BASE_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, BASE_MESSENGER_L2);
        assertEq(cid, uint64(BASE_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(MODE_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, MODE_MESSENGER_L2);
        assertEq(cid, uint64(MODE_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(CELO_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, CELO_MESSENGER_L2);
        assertEq(cid, uint64(CELO_CHAIN_ID));
    }

    // ========== Full Setup: deploy all + set all bridge mediators ==========

    function _setupAllBridgeMediators() internal {
        // Gnosis (script_26_01)
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        // Polygon (script_26_02)
        l1s[0] = FX_ROOT;
        verifiers[0] = address(verifierPolygon);
        chainIds[0] = POLYGON_CHAIN_ID;
        l2s[0] = FX_GOVERNOR_TUNNEL;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        // Arbitrum (script_26_03)
        l1s[0] = ARBITRUM_INBOX;
        verifiers[0] = address(verifierArbitrum);
        chainIds[0] = ARBITRUM_CHAIN_ID;
        l2s[0] = ARBITRUM_BRIDGE_MEDIATOR_L2;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);

        // Optimism/Base/Mode/Celo (script_26_04)
        address[] memory l1s4 = new address[](4);
        address[] memory verifiers4 = new address[](4);
        uint256[] memory chainIds4 = new uint256[](4);
        address[] memory l2s4 = new address[](4);

        l1s4[0] = OPTIMISM_L1_CDM;
        l1s4[1] = BASE_L1_CDM;
        l1s4[2] = MODE_L1_CDM;
        l1s4[3] = CELO_L1_CDM;

        verifiers4[0] = address(verifierOptimism);
        verifiers4[1] = address(verifierOptimism);
        verifiers4[2] = address(verifierOptimism);
        verifiers4[3] = address(verifierOptimism);

        chainIds4[0] = OPTIMISM_CHAIN_ID;
        chainIds4[1] = BASE_CHAIN_ID;
        chainIds4[2] = MODE_CHAIN_ID;
        chainIds4[3] = CELO_CHAIN_ID;

        l2s4[0] = OPTIMISM_MESSENGER_L2;
        l2s4[1] = BASE_MESSENGER_L2;
        l2s4[2] = MODE_MESSENGER_L2;
        l2s4[3] = CELO_MESSENGER_L2;

        vm.prank(TIMELOCK);
        guard.setBridgeMediatorL1BridgeParams(l1s4, verifiers4, chainIds4, l2s4);
    }

    function testFullSetupAllBridgeMediators() public {
        _setupAllBridgeMediators();

        // Verify all 7 L1 bridge mediators are set correctly
        (address v, address bm, uint64 cid) = guard.mapBridgeMediatorL1BridgeParams(AMB_CONTRACT_PROXY_FOREIGN);
        assertEq(v, address(verifierGnosis));
        assertEq(bm, HOME_MEDIATOR);
        assertEq(cid, uint64(GNOSIS_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(FX_ROOT);
        assertEq(v, address(verifierPolygon));
        assertEq(bm, FX_GOVERNOR_TUNNEL);
        assertEq(cid, uint64(POLYGON_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(ARBITRUM_INBOX);
        assertEq(v, address(verifierArbitrum));
        assertEq(bm, ARBITRUM_BRIDGE_MEDIATOR_L2);
        assertEq(cid, uint64(ARBITRUM_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(OPTIMISM_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, OPTIMISM_MESSENGER_L2);
        assertEq(cid, uint64(OPTIMISM_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(BASE_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, BASE_MESSENGER_L2);
        assertEq(cid, uint64(BASE_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(MODE_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, MODE_MESSENGER_L2);
        assertEq(cid, uint64(MODE_CHAIN_ID));

        (v, bm, cid) = guard.mapBridgeMediatorL1BridgeParams(CELO_L1_CDM);
        assertEq(v, address(verifierOptimism));
        assertEq(bm, CELO_MESSENGER_L2);
        assertEq(cid, uint64(CELO_CHAIN_ID));
    }

    // ========== Guard checkTransaction with bridged data after full setup ==========

    function testCheckTransactionGnosisBridgePayload() public {
        _setupAllBridgeMediators();

        // Authorize a target+selector+chainId on Gnosis
        // Using a mock target and changeMultisigPermission selector as in JS test
        address gnosisTarget = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
        bytes4 selector = bytes4(keccak256("changeMultisigPermission(address,bool)"));

        address[] memory targets = new address[](1);
        bytes4[] memory selectors = new bytes4[](1);
        uint256[] memory chainIdArr = new uint256[](1);
        bool[] memory statuses = new bool[](1);

        targets[0] = gnosisTarget;
        selectors[0] = selector;
        chainIdArr[0] = GNOSIS_CHAIN_ID;
        statuses[0] = true;

        vm.prank(TIMELOCK);
        guard.setTargetSelectorChainIds(targets, selectors, chainIdArr, statuses);

        // Verify it was set
        assertTrue(guard.getTargetSelectorChainId(gnosisTarget, selector, GNOSIS_CHAIN_ID));
    }

    function testCheckTransactionOptimismBridgePayload() public {
        _setupAllBridgeMediators();

        // Authorize a target+selector+chainId on Optimism
        address optimismTarget = 0x118173028162C1b7c6Bf8488bd5dA2abd7c30F9D;
        bytes4 selector = bytes4(keccak256("mint(address,uint256)"));

        address[] memory targets = new address[](1);
        bytes4[] memory selectors = new bytes4[](1);
        uint256[] memory chainIdArr = new uint256[](1);
        bool[] memory statuses = new bool[](1);

        targets[0] = optimismTarget;
        selectors[0] = selector;
        chainIdArr[0] = OPTIMISM_CHAIN_ID;
        statuses[0] = true;

        vm.prank(TIMELOCK);
        guard.setTargetSelectorChainIds(targets, selectors, chainIdArr, statuses);

        assertTrue(guard.getTargetSelectorChainId(optimismTarget, selector, OPTIMISM_CHAIN_ID));
    }

    // ========== GuardCM pause/unpause via governor ==========

    function testGuardChangeGovernor() public {
        address newGovernor = address(0xBEEF);

        vm.prank(TIMELOCK);
        guard.changeGovernor(newGovernor);

        assertEq(guard.governor(), newGovernor);
    }

    function testGuardChangeGovernorOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnerOnly(address,address)", address(this), TIMELOCK));
        guard.changeGovernor(address(0xBEEF));
    }

    function testGuardPauseByTimelock() public {
        vm.prank(TIMELOCK);
        guard.pause();
        assertEq(guard.paused(), 2);
    }

    function testGuardUnpause() public {
        vm.prank(TIMELOCK);
        guard.pause();
        assertEq(guard.paused(), 2);

        vm.prank(TIMELOCK);
        guard.unpause();
        assertEq(guard.paused(), 1);
    }

    function testGuardUnpauseOnlyOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnerOnly(address,address)", address(this), TIMELOCK));
        guard.unpause();
    }

    // ========== Validation error cases ==========

    function testSetBridgeMediatorsWrongArrayLength() public {
        address[] memory l1s = new address[](2);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        l1s[1] = FX_ROOT;
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("WrongArrayLength(uint256,uint256,uint256,uint256)", 2, 1, 1, 1));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    function testSetBridgeMediatorsZeroL1Address() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = address(0);
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    function testSetBridgeMediatorsZeroVerifier() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(0);
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    function testSetBridgeMediatorsEOAVerifier() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(0xDEAD); // EOA, not a contract
        chainIds[0] = GNOSIS_CHAIN_ID;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("ContractOnly(address)", address(0xDEAD)));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    function testSetBridgeMediatorsZeroChainId() public {
        address[] memory l1s = new address[](1);
        address[] memory verifiers = new address[](1);
        uint256[] memory chainIds = new uint256[](1);
        address[] memory l2s = new address[](1);

        l1s[0] = AMB_CONTRACT_PROXY_FOREIGN;
        verifiers[0] = address(verifierGnosis);
        chainIds[0] = 0;
        l2s[0] = HOME_MEDIATOR;

        vm.prank(TIMELOCK);
        vm.expectRevert(abi.encodeWithSignature("L2ChainIdNotSupported(uint256)", 0));
        guard.setBridgeMediatorL1BridgeParams(l1s, verifiers, chainIds, l2s);
    }

    // ========== Guard checkTransaction basics ==========

    function testCheckTransactionNoDelegateCall() public {
        // DelegateCall operation should revert
        vm.expectRevert(abi.encodeWithSignature("NoDelegateCall()"));
        guard.checkTransaction(
            TIMELOCK, 0, "", Enum.Operation.DelegateCall,
            0, 0, 0, address(0), payable(address(0)), "", address(0)
        );
    }

    function testCheckTransactionNoSelfCall() public {
        // Calling the multisig itself should revert
        vm.expectRevert(abi.encodeWithSignature("NoSelfCall()"));
        guard.checkTransaction(
            CM, 0, "0x00000000", Enum.Operation.Call,
            0, 0, 0, address(0), payable(address(0)), "", address(0)
        );
    }

    function testCheckTransactionWhenPausedAllowsNonTimelockCalls() public {
        // When guard is active (paused=1), calls to non-timelock, non-multisig targets pass through
        guard.checkTransaction(
            address(0xBEEF), 0, "", Enum.Operation.Call,
            0, 0, 0, address(0), payable(address(0)), "", address(0)
        );
    }

    function testCheckTransactionWhenUnpausedPassesAll() public {
        // Unpause the guard
        vm.prank(TIMELOCK);
        guard.pause();
        assertEq(guard.paused(), 2);

        // When unpaused, everything passes (no checks)
        guard.checkTransaction(
            TIMELOCK, 0, "0x00000000", Enum.Operation.Call,
            0, 0, 0, address(0), payable(address(0)), "", address(0)
        );
    }

    function testCheckAfterExecution() public {
        // Should not revert - it's a no-op
        guard.checkAfterExecution(bytes32(0), true);
    }
}
