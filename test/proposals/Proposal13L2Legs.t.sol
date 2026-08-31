// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal13Builder} from "../../scripts/proposals/proposal_13/Proposal13Housekeeping.s.sol";

interface IStakingVerifier {
    function owner() external view returns (address);
    function implementationsCheck() external view returns (bool);
    function mapImplementations(address implementation) external view returns (bool);
    function verifyImplementation(address implementation) external view returns (bool);
}

interface IServiceRegistryL2 {
    function owner() external view returns (address);
    function mapMultisigs(address multisig) external view returns (bool);
}

interface IBridgeMediator {
    function processMessageFromSource(bytes memory data) external;
    function processMessageFromRoot(uint256 stateId, address rootMessageSender, bytes memory data) external;
}

/// @notice Destination-chain validation for proposal 13's two bridged entries, replaying the exact
///         packed buffers the proposal carries.
///
///         The repo convention is to validate L2 effects with Tenderly. That works for Polygon and
///         is recorded in scripts/proposals/proposal_13/README.md, but **Tenderly does not support
///         Mode (34443)** — it is absent from the public-networks list and simulation returns a 500.
///         These fork tests are the substitute, and they are run for BOTH chains so the two legs are
///         validated the same way rather than one being weaker than the other.
///
///         Run:
///           MODE_RPC=https://mainnet.mode.network forge test --match-contract Proposal13ModeLegTest -vvv
///           POLYGON_RPC=<rpc> forge test --match-contract Proposal13PolygonLegTest -vvv
contract Proposal13ModeLegTest is Test, Proposal13Builder {
    address internal constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;
    /// @dev The implementation Mode's 7 live staking proxies were created against. It must keep
    ///      verifying after this proposal — that is what proves the change is surgical.
    address internal constant MODE_LIVE_IMPLEMENTATION = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;

    function test_mode_deallowlistsV1AndKeepsCheckOn() public {
        vm.createSelectFork(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")));

        IStakingVerifier sv = IStakingVerifier(MODE_STAKING_VERIFIER);

        // Preconditions, with a control so a later `false` is a real change and not a dead getter.
        assertEq(sv.owner(), MODE_MESSENGER_L2, "StakingVerifier owner is not the Mode mediator");
        assertTrue(sv.implementationsCheck(), "implementationsCheck already off");
        assertTrue(sv.mapImplementations(MODE_V1_IMPLEMENTATION), "V1 implementation not currently allowlisted");
        assertTrue(sv.verifyImplementation(MODE_V1_IMPLEMENTATION), "V1 does not currently verify");
        assertTrue(sv.verifyImplementation(MODE_LIVE_IMPLEMENTATION), "live implementation does not currently verify");

        // The mediator authorises on the messenger's cross-domain sender being the L1 Timelock.
        vm.mockCall(
            L2_MESSENGER,
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(TIMELOCK)
        );

        vm.prank(L2_MESSENGER);
        IBridgeMediator(MODE_MESSENGER_L2).processMessageFromSource(modeBridgePayload());

        // The effect.
        assertFalse(sv.mapImplementations(MODE_V1_IMPLEMENTATION), "V1 implementation still allowlisted");
        assertFalse(sv.verifyImplementation(MODE_V1_IMPLEMENTATION), "V1 still verifies");

        // The guard that matters: setCheck was passed as true, so the allowlist stays ENFORCED.
        // Had it been false, verifyImplementation would return true for everything.
        assertTrue(sv.implementationsCheck(), "allowlist was switched off - setCheck was not true");

        // Surgical: the implementation Mode's 7 live proxies use is untouched and still verifies.
        // If setCheck had been passed as false this assertion would still pass, which is exactly why
        // the implementationsCheck assertion above is the load-bearing one.
        assertTrue(sv.verifyImplementation(MODE_LIVE_IMPLEMENTATION), "live implementation stopped verifying");
        assertTrue(sv.mapImplementations(MODE_LIVE_IMPLEMENTATION), "live implementation was de-allowlisted");

        console2.log("Mode leg: V1 de-allowlisted, implementationsCheck still enforced");
    }

    /// @dev The mediator must reject a message whose L1 origin is not the Timelock.
    function test_mode_rejectsForeignRootSender() public {
        vm.createSelectFork(vm.envOr("MODE_RPC", string("https://mainnet.mode.network")));
        vm.mockCall(
            L2_MESSENGER,
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(0xBEEF))
        );
        vm.prank(L2_MESSENGER);
        // Pinned, not a bare expectRevert: a bare one would also pass if the call failed for an unrelated
        // reason — a malformed buffer, or a mock that silently did not apply.
        vm.expectRevert(
            abi.encodeWithSignature("SourceGovernorOnly(address,address)", address(0xBEEF), TIMELOCK)
        );
        IBridgeMediator(MODE_MESSENGER_L2).processMessageFromSource(modeBridgePayload());
    }
}

contract Proposal13PolygonLegTest is Test, Proposal13Builder {
    address internal constant FX_CHILD = 0x8397259c983751DAf40400790063935a11afa28a;

    function test_polygon_dewhitelistsPolySafeCreator() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon-bor-rpc.publicnode.com")));

        IServiceRegistryL2 sr = IServiceRegistryL2(POLYGON_SERVICE_REGISTRY_L2);
        address gnosisSafeMultisig = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;

        assertEq(sr.owner(), FX_TUNNEL_L2, "ServiceRegistryL2 owner is not the FxGovernorTunnel");
        assertTrue(sr.mapMultisigs(POLYSAFE_CREATOR), "PolySafe creator not currently whitelisted");
        assertTrue(sr.mapMultisigs(gnosisSafeMultisig), "control: GnosisSafeMultisig not whitelisted");

        vm.prank(FX_CHILD);
        IBridgeMediator(FX_TUNNEL_L2).processMessageFromRoot(1, TIMELOCK, polygonBridgePayload());

        assertFalse(sr.mapMultisigs(POLYSAFE_CREATOR), "PolySafe creator still whitelisted");
        // The fallback path for services must survive untouched.
        assertTrue(sr.mapMultisigs(gnosisSafeMultisig), "GnosisSafeMultisig was disturbed");

        console2.log("Polygon leg: PolySafe creator de-whitelisted, GnosisSafeMultisig untouched");
    }

    /// @dev The tunnel must reject a message whose root sender is not the Timelock.
    function test_polygon_rejectsForeignRootSender() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon-bor-rpc.publicnode.com")));
        vm.prank(FX_CHILD);
        vm.expectRevert(
            abi.encodeWithSignature("RootGovernorOnly(address,address)", address(0xBEEF), TIMELOCK)
        );
        IBridgeMediator(FX_TUNNEL_L2).processMessageFromRoot(1, address(0xBEEF), polygonBridgePayload());
    }
}
