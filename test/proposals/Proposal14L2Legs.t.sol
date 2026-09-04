// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal14Builder} from "../../scripts/proposals/proposal_14/Proposal14WithheldSync.s.sol";

interface ITargetDispenserL2 {
    function withheldAmount() external view returns (uint256);
    function stakingBatchNonce() external view returns (uint256);
    function owner() external view returns (address);
    function olas() external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IReceiverFx {
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external;
}

interface IReceiverAmb {
    function processMessageFromForeign(bytes memory data) external;
}

interface IReceiverOp {
    function processMessageFromSource(bytes memory data) external payable;
}

/// @notice Destination-chain validation for proposal 14. Each leg replays the proposal's OWN packed
///         buffer (`packedFor`) through that chain's governance receiver, pranked from the bridge
///         that would deliver it, and asserts the dispenser ends up synced.
///
///         What each leg proves that the L1 test cannot: that the wire format is right. Polygon
///         carries the packed buffer directly, while Gnosis and the OP-stack chains wrap it in an
///         encoded `processMessageFrom…` call — a mix-up there reverts on the destination chain,
///         long after the vote.
abstract contract Proposal14LegBase is Test, Proposal14Builder {
    function _assertSynced(address dispenser) internal view {
        // Only sub-decimal dust may remain: the amount is normalised to the bridge's decimals.
        assertLt(ITargetDispenserL2(dispenser).withheldAmount(), 1e12, "not synced down to dust");
        assertEq(ITargetDispenserL2(dispenser).stakingBatchNonce(), 1, "batch nonce did not advance");
    }

    /// @dev Before the sync, the dispenser's whole OLAS balance is withheld. If that stops holding,
    ///      the sync would report more than the dispenser can actually pay out later.
    function _assertPrecondition(address dispenser) internal view {
        uint256 withheld = ITargetDispenserL2(dispenser).withheldAmount();
        console2.log("withheld", withheld);
        assertGt(withheld, 0, "nothing to sync on this chain");
        assertEq(withheld, IERC20(ITargetDispenserL2(dispenser).olas()).balanceOf(dispenser), "withheld != balance");
        assertEq(ITargetDispenserL2(dispenser).stakingBatchNonce(), 0, "a sync has already happened");
    }
}

contract Proposal14PolygonLegTest is Proposal14LegBase {
    address internal constant FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;

    function setUp() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon-bor-rpc.publicnode.com")));
    }

    function test_polygonLegSyncs() public {
        _assertPrecondition(POLYGON_DISPENSER_L2);
        vm.prank(FX_CHILD);
        IReceiverFx(FX_TUNNEL_L2).processMessageFromRoot(1, TIMELOCK, packedFor(POLYGON_DISPENSER_L2, ""));
        _assertSynced(POLYGON_DISPENSER_L2);
    }

    function test_polygonLegRejectsForeignRootSender() public {
        vm.prank(FX_CHILD);
        vm.expectRevert(abi.encodeWithSignature("RootGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        IReceiverFx(FX_TUNNEL_L2).processMessageFromRoot(1, address(0xBAD), packedFor(POLYGON_DISPENSER_L2, ""));
    }
}

contract Proposal14GnosisLegTest is Proposal14LegBase {
    address internal constant AMB_HOME = 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59;

    function setUp() public {
        vm.createSelectFork(vm.envOr("GNOSIS_RPC", string("https://rpc.gnosischain.com")));
    }

    function test_gnosisLegSyncs() public {
        _assertPrecondition(GNOSIS_DISPENSER_L2);
        vm.mockCall(AMB_HOME, abi.encodeWithSignature("messageSender()"), abi.encode(TIMELOCK));
        vm.prank(AMB_HOME);
        IReceiverAmb(GNOSIS_MEDIATOR_L2)
            .processMessageFromForeign(packedFor(GNOSIS_DISPENSER_L2, abi.encode(RETURN_GAS)));
        _assertSynced(GNOSIS_DISPENSER_L2);
    }

    function test_gnosisLegRejectsForeignGovernor() public {
        vm.mockCall(AMB_HOME, abi.encodeWithSignature("messageSender()"), abi.encode(address(0xBAD)));
        vm.prank(AMB_HOME);
        vm.expectRevert(abi.encodeWithSignature("ForeignGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        IReceiverAmb(GNOSIS_MEDIATOR_L2)
            .processMessageFromForeign(packedFor(GNOSIS_DISPENSER_L2, abi.encode(RETURN_GAS)));
    }
}

abstract contract Proposal14OpLegBase is Proposal14LegBase {
    address internal constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;

    function _opSyncs(address messengerL2, address dispenser) internal {
        _assertPrecondition(dispenser);
        vm.mockCall(L2_MESSENGER, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(TIMELOCK));
        vm.prank(L2_MESSENGER);
        IReceiverOp(messengerL2).processMessageFromSource(packedFor(dispenser, abi.encode(RETURN_GAS)));
        _assertSynced(dispenser);
    }

    function _opRejectsForeign(address messengerL2, address dispenser) internal {
        vm.mockCall(L2_MESSENGER, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(address(0xBAD)));
        vm.prank(L2_MESSENGER);
        vm.expectRevert(abi.encodeWithSignature("SourceGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        IReceiverOp(messengerL2).processMessageFromSource(packedFor(dispenser, abi.encode(RETURN_GAS)));
    }
}

contract Proposal14OptimismLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("OPTIMISM_RPC", string("https://mainnet.optimism.io")));
    }

    function test_optimismLegSyncs() public {
        _opSyncs(OPTIMISM_MESSENGER_L2, OPTIMISM_DISPENSER_L2);
    }

    function test_optimismLegRejectsForeignGovernor() public {
        _opRejectsForeign(OPTIMISM_MESSENGER_L2, OPTIMISM_DISPENSER_L2);
    }
}

contract Proposal14BaseLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("BASE_RPC", string("https://mainnet.base.org")));
    }

    function test_baseLegSyncs() public {
        _opSyncs(BASE_MESSENGER_L2, BASE_DISPENSER_L2);
    }

    function test_baseLegRejectsForeignGovernor() public {
        _opRejectsForeign(BASE_MESSENGER_L2, BASE_DISPENSER_L2);
    }
}

contract Proposal14CeloLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("CELO_RPC", string("https://forno.celo.org")));
    }

    function test_celoLegSyncs() public {
        _opSyncs(CELO_MESSENGER_L2, CELO_DISPENSER_L2);
    }

    function test_celoLegRejectsForeignGovernor() public {
        _opRejectsForeign(CELO_MESSENGER_L2, CELO_DISPENSER_L2);
    }
}

contract Proposal14ModeLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")));
    }

    function test_modeLegSyncs() public {
        _opSyncs(MODE_MESSENGER_L2, MODE_DISPENSER_L2);
    }

    function test_modeLegRejectsForeignGovernor() public {
        _opRejectsForeign(MODE_MESSENGER_L2, MODE_DISPENSER_L2);
    }
}

/// @notice Arbitrum has no governance receiver: the dispenser's owner is the L1 Timelock's L2 alias,
///         so the retryable ticket calls the dispenser directly and arrives already authorised.
///
///         `sendTxToL1` is the ArbSys precompile at 0x64, which a plain EVM fork does not implement
///         (the unmocked call dies with InvalidFEOpcode). It is mocked here so the rest of the leg
///         is covered; that the real precompile accepts this call was established separately by an
///         eth_call against a live Nitro node, recorded in the README.
contract Proposal14ArbitrumLegTest is Proposal14LegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_RPC", string("https://arb1.arbitrum.io/rpc")));
    }

    function test_arbitrumOwnerIsTheTimelockAlias() public view {
        address alias_ = address(uint160(TIMELOCK) + uint160(0x1111000000000000000000000000000000001111));
        assertEq(ITargetDispenserL2(ARBITRUM_DISPENSER_L2).owner(), alias_, "owner is not the Timelock alias");
    }

    function test_arbitrumLegSyncs() public {
        _assertPrecondition(ARBITRUM_DISPENSER_L2);
        address alias_ = address(uint160(TIMELOCK) + uint160(0x1111000000000000000000000000000000001111));
        vm.mockCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)));
        vm.prank(alias_);
        (bool ok,) = ARBITRUM_DISPENSER_L2.call(syncCalldata(""));
        assertTrue(ok, "aliased Timelock could not sync");
        _assertSynced(ARBITRUM_DISPENSER_L2);
    }

    function test_arbitrumLegRejectsAnyoneElse() public {
        vm.mockCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)));
        vm.prank(address(0xBAD));
        (bool ok,) = ARBITRUM_DISPENSER_L2.call(syncCalldata(""));
        assertFalse(ok, "a non-owner was able to sync");
    }
}
