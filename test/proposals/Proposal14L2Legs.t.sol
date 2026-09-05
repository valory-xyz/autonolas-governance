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

/// @notice Destination-chain validation for proposal 14.
///
///         Every leg takes its input from `buildProposal()` and delivers the EXACT BYTES the bridge
///         would deliver — the `_message` out of `sendMessage`, the `_data` out of
///         `requireToPassMessage`, the packed buffer out of `sendMessageToChild`, the `data` out of
///         `createRetryableTicket` — by low-level call. Nothing here re-encodes a wrapper or names a
///         receiver by hand, because a test that picks its own wrapper cannot disagree with the
///         builder about the wire format, and the wire format is the thing most likely to be wrong:
///         Polygon takes the packed buffer directly while Gnosis and the OP-stack chains need it
///         wrapped in a `processMessageFrom…` call, and the L1 leg succeeds either way.
///
///         The receiver and dispenser addresses are likewise read out of the calldata and then
///         checked against this chain's expected constants, so a mispaired
///         (L1 entrypoint, L2 receiver, dispenser) triple fails here rather than on the day.
abstract contract Proposal14LegBase is Test, Proposal14Builder {
    /// @dev Pulls one entry out of the proposal and splits it into what L1 sends and what the bridge
    ///      hands to the receiver. `delivered` is raw calldata for every route except Polygon, whose
    ///      FxChild wraps the buffer in `processMessageFromRoot` itself.
    function _leg(uint256 i) internal pure returns (address l1Target, address l2Receiver, bytes memory delivered) {
        (address[] memory targets,, bytes[] memory calldatas,) = buildProposal();
        l1Target = targets[i];
        bytes memory args = _stripSelector(calldatas[i]);
        bytes4 sel = bytes4(calldatas[i]);

        if (sel == bytes4(keccak256("sendMessage(address,bytes,uint32)"))) {
            (l2Receiver, delivered,) = abi.decode(args, (address, bytes, uint32));
        } else if (sel == bytes4(keccak256("requireToPassMessage(address,bytes,uint256)"))) {
            (l2Receiver, delivered,) = abi.decode(args, (address, bytes, uint256));
        } else if (sel == bytes4(keccak256("sendMessageToChild(address,bytes)"))) {
            (address tunnel, bytes memory packed) = abi.decode(args, (address, bytes));
            l2Receiver = tunnel;
            // FxChild — not this proposal — calls processMessageFromRoot with the buffer.
            delivered =
                abi.encodeWithSignature("processMessageFromRoot(uint256,address,bytes)", uint256(1), TIMELOCK, packed);
        } else if (
            sel
                == bytes4(
                    keccak256("createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)")
                )
        ) {
            (l2Receiver,,,,,,, delivered) =
                abi.decode(args, (address, uint256, uint256, address, address, uint256, uint256, bytes));
        } else {
            revert("unrecognised L1 selector - the builder changed shape");
        }
    }

    /// @dev The dispenser the packed buffer actually targets, read out of the buffer's first 20 bytes.
    ///      `delivered` for the wrapped routes is `processMessageFrom…(bytes)`, so the buffer sits one
    ///      abi.decode in; Polygon's is nested one level deeper by the FxChild wrapper above.
    function _bufferTarget(bytes memory delivered, bool polygonShape) internal pure returns (address target) {
        bytes memory packed;
        if (polygonShape) {
            (,, packed) = abi.decode(_stripSelector(delivered), (uint256, address, bytes));
        } else {
            packed = abi.decode(_stripSelector(delivered), (bytes));
        }
        assembly {
            target := shr(96, mload(add(packed, 32)))
        }
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(data.length - 4);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[i + 4];
        }
    }

    function _assertPrecondition(address dispenser) internal view {
        uint256 withheld = ITargetDispenserL2(dispenser).withheldAmount();
        console2.log("withheld", withheld);
        assertGt(withheld, 0, "nothing to sync on this chain");
        assertEq(withheld, IERC20(ITargetDispenserL2(dispenser).olas()).balanceOf(dispenser), "withheld != balance");
        assertEq(ITargetDispenserL2(dispenser).stakingBatchNonce(), 0, "a sync has already happened");
    }

    function _assertSynced(address dispenser) internal view {
        // Only sub-decimal dust may remain: the amount is normalised to the bridge's decimals.
        assertLt(ITargetDispenserL2(dispenser).withheldAmount(), 1e12, "not synced down to dust");
        assertEq(ITargetDispenserL2(dispenser).stakingBatchNonce(), 1, "batch nonce did not advance");
    }

    /// @dev Deliver the builder's own bytes, from the bridge that would deliver them.
    function _deliver(address bridge, address receiver, bytes memory delivered) internal {
        vm.prank(bridge);
        (bool ok, bytes memory ret) = receiver.call(delivered);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

contract Proposal14PolygonLegTest is Proposal14LegBase {
    address internal constant FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;

    function setUp() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon-bor-rpc.publicnode.com")));
    }

    function test_polygonLegSyncs() public {
        (address l1Target, address receiver, bytes memory delivered) = _leg(0);
        assertEq(l1Target, FX_ROOT, "entry [0] does not go through FxRoot");
        assertEq(receiver, FX_TUNNEL_L2, "entry [0] wrong L2 receiver");
        assertEq(_bufferTarget(delivered, true), POLYGON_DISPENSER_L2, "entry [0] wrong dispenser");

        _assertPrecondition(POLYGON_DISPENSER_L2);
        _deliver(FX_CHILD, receiver, delivered);
        _assertSynced(POLYGON_DISPENSER_L2);
    }

    function test_polygonLegRejectsForeignRootSender() public {
        (, address receiver,) = _leg(0);
        (,, bytes memory packed) = abi.decode(_stripSelector(_delivered(0)), (uint256, address, bytes));
        vm.prank(FX_CHILD);
        vm.expectRevert(abi.encodeWithSignature("RootGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        (bool ok,) = receiver.call(
            abi.encodeWithSignature("processMessageFromRoot(uint256,address,bytes)", uint256(1), address(0xBAD), packed)
        );
        ok; // the expectRevert above is the assertion
    }

    function _delivered(uint256 i) internal pure returns (bytes memory d) {
        (,, d) = _leg(i);
    }
}

contract Proposal14GnosisLegTest is Proposal14LegBase {
    address internal constant AMB_HOME = 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59;

    function setUp() public {
        vm.createSelectFork(vm.envOr("GNOSIS_RPC", string("https://rpc.gnosischain.com")));
    }

    function test_gnosisLegSyncs() public {
        (address l1Target, address receiver, bytes memory delivered) = _leg(1);
        assertEq(l1Target, AMB_FOREIGN, "entry [1] does not go through the AMB");
        assertEq(receiver, GNOSIS_MEDIATOR_L2, "entry [1] wrong L2 receiver");
        assertEq(bytes4(delivered), bytes4(keccak256("processMessageFromForeign(bytes)")), "entry [1] wrong wrapper");
        assertEq(_bufferTarget(delivered, false), GNOSIS_DISPENSER_L2, "entry [1] wrong dispenser");

        _assertPrecondition(GNOSIS_DISPENSER_L2);
        vm.mockCall(AMB_HOME, abi.encodeWithSignature("messageSender()"), abi.encode(TIMELOCK));
        _deliver(AMB_HOME, receiver, delivered);
        _assertSynced(GNOSIS_DISPENSER_L2);
    }

    function test_gnosisLegRejectsForeignGovernor() public {
        (, address receiver, bytes memory delivered) = _leg(1);
        vm.mockCall(AMB_HOME, abi.encodeWithSignature("messageSender()"), abi.encode(address(0xBAD)));
        vm.prank(AMB_HOME);
        vm.expectRevert(abi.encodeWithSignature("ForeignGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        (bool ok,) = receiver.call(delivered);
        ok;
    }
}

abstract contract Proposal14OpLegBase is Proposal14LegBase {
    address internal constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;

    function _opSyncs(uint256 i, address expectedL1, address expectedReceiver, address dispenser) internal {
        (address l1Target, address receiver, bytes memory delivered) = _leg(i);
        assertEq(l1Target, expectedL1, "entry goes through the wrong L1 messenger");
        assertEq(receiver, expectedReceiver, "entry has the wrong L2 receiver");
        assertEq(bytes4(delivered), bytes4(keccak256("processMessageFromSource(bytes)")), "entry has the wrong wrapper");
        assertEq(_bufferTarget(delivered, false), dispenser, "entry targets the wrong dispenser");

        _assertPrecondition(dispenser);
        vm.mockCall(L2_MESSENGER, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(TIMELOCK));
        _deliver(L2_MESSENGER, receiver, delivered);
        _assertSynced(dispenser);
    }

    function _opRejectsForeign(uint256 i) internal {
        (, address receiver, bytes memory delivered) = _leg(i);
        vm.mockCall(L2_MESSENGER, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(address(0xBAD)));
        vm.prank(L2_MESSENGER);
        vm.expectRevert(abi.encodeWithSignature("SourceGovernorOnly(address,address)", address(0xBAD), TIMELOCK));
        (bool ok,) = receiver.call(delivered);
        ok;
    }
}

contract Proposal14OptimismLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("OPTIMISM_RPC", string("https://mainnet.optimism.io")));
    }

    function test_optimismLegSyncs() public {
        _opSyncs(2, OPTIMISM_L1CDM, OPTIMISM_MESSENGER_L2, OPTIMISM_DISPENSER_L2);
    }

    function test_optimismLegRejectsForeignGovernor() public {
        _opRejectsForeign(2);
    }
}

contract Proposal14BaseLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("BASE_RPC", string("https://mainnet.base.org")));
    }

    function test_baseLegSyncs() public {
        _opSyncs(3, BASE_L1CDM, BASE_MESSENGER_L2, BASE_DISPENSER_L2);
    }

    function test_baseLegRejectsForeignGovernor() public {
        _opRejectsForeign(3);
    }
}

contract Proposal14CeloLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("CELO_RPC", string("https://forno.celo.org")));
    }

    function test_celoLegSyncs() public {
        _opSyncs(4, CELO_L1CDM, CELO_MESSENGER_L2, CELO_DISPENSER_L2);
    }

    function test_celoLegRejectsForeignGovernor() public {
        _opRejectsForeign(4);
    }
}

contract Proposal14ModeLegTest is Proposal14OpLegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")));
    }

    function test_modeLegSyncs() public {
        _opSyncs(5, MODE_L1CDM, MODE_MESSENGER_L2, MODE_DISPENSER_L2);
    }

    function test_modeLegRejectsForeignGovernor() public {
        _opRejectsForeign(5);
    }
}

/// @notice Arbitrum has no governance receiver: the dispenser's owner is the L1 Timelock's L2 alias,
///         so the retryable ticket calls the dispenser directly and arrives already authorised.
///
///         `sendTxToL1` is the ArbSys precompile at 0x64, which a plain EVM fork does not implement
///         (the unmocked call dies with InvalidFEOpcode). It is mocked here so the rest of the leg is
///         covered; that the real precompile accepts this call was established by an eth_call against
///         a live Nitro node, recorded in the README.
contract Proposal14ArbitrumLegTest is Proposal14LegBase {
    function setUp() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_RPC", string("https://arb1.arbitrum.io/rpc")));
    }

    function _alias() internal pure returns (address) {
        return address(uint160(TIMELOCK) + uint160(0x1111000000000000000000000000000000001111));
    }

    function test_arbitrumOwnerIsTheTimelockAlias() public view {
        assertEq(ITargetDispenserL2(ARBITRUM_DISPENSER_L2).owner(), _alias(), "owner is not the Timelock alias");
    }

    function test_arbitrumLegSyncs() public {
        (address l1Target, address to, bytes memory delivered) = _leg(6);
        assertEq(l1Target, ARBITRUM_INBOX, "entry [6] does not go through the Inbox");
        assertEq(to, ARBITRUM_DISPENSER_L2, "entry [6] wrong dispenser");
        assertEq(bytes4(delivered), bytes4(keccak256("syncWithheldAmount(bytes)")), "entry [6] wrong call");

        _assertPrecondition(ARBITRUM_DISPENSER_L2);
        vm.mockCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)));
        _deliver(_alias(), to, delivered);
        _assertSynced(ARBITRUM_DISPENSER_L2);
    }

    function test_arbitrumLegRejectsAnyoneElse() public {
        (, address to, bytes memory delivered) = _leg(6);
        vm.mockCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)));
        vm.prank(address(0xBAD));
        (bool ok,) = to.call(delivered);
        assertFalse(ok, "a non-owner was able to sync");
    }
}
