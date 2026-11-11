// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Proposal17Activation} from "../../scripts/proposals/proposal_17/Proposal17Activation.s.sol";

interface IMediator {
    function processMessageFromSource(bytes memory data) external;              // OP-stack messengers
    function processMessageFromRoot(uint256, address, bytes memory) external;   // FxGovernorTunnel
    function processMessageFromForeign(bytes memory data) external;             // Gnosis HomeMediator
    function CDMContractProxyHome() external view returns (address);            // OP-stack relayer
    function AMBContractProxyHome() external view returns (address);            // Gnosis AMB
    function fxChild() external view returns (address);                        // Polygon FxChild
}

// Destination-leg validation for proposal 17 (Pia's check #2). Each test forks the destination chain,
// simulates the bridge delivering that chain's message to its mediator (or the aliased Timelock for
// Arbitrum/Robinhood), and asserts that every inner call in the proposal took effect — derived
// generically from the proposal's own calldata, so the assertions cannot drift from the payload.
//
// Run (public RPC defaults; override with env):
//   GNOSIS_RPC=.. OPTIMISM_RPC=.. BASE_RPC=.. CELO_RPC=.. MODE_RPC=.. POLYGON_RPC=.. ARBITRUM_RPC=.. ROBINHOOD_RPC=.. \
//   forge test --match-contract Proposal17L2Legs -vv
contract Proposal17L2Legs is Test {
    Proposal17Activation internal p;

    address internal constant TIMELOCK   = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant TL_ALIAS   = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F; // aliased Timelock (arb/rh)
    address internal constant OP_L2_XDM  = 0x4200000000000000000000000000000000000007; // L2CrossDomainMessenger predeploy
    address internal constant FX_CHILD   = 0x8397259c983751DAf40400790063935a11afa28a; // polygon
    address internal constant AMB_HOME   = 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59; // gnosis AMB (home)

    // L2 mediators (owner of the L2 targets)
    address internal constant GNOSIS_MEDIATOR    = 0x15bd56669F57192a97dF41A2aa8f4403e9491776;
    address internal constant FX_TUNNEL          = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address internal constant OPTIMISM_MESSENGER = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c;
    address internal constant BASE_MESSENGER     = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant CELO_MESSENGER     = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d;
    address internal constant MODE_MESSENGER     = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;

    function setUp() public { p = new Proposal17Activation(); vm.makePersistent(address(p)); }

    // ---- generic effect assertions, derived from the proposal's own calls ----
    function _tail(bytes memory d) internal pure returns (bytes memory t) {
        t = new bytes(d.length - 4);
        for (uint256 i; i < t.length; ++i) t[i] = d[i + 4];
    }
    function _sc_addr(address target, string memory sig, bytes memory a) internal view returns (address) {
        (bool ok, bytes memory r) = target.staticcall(bytes.concat(bytes4(keccak256(bytes(sig))), a));
        require(ok, "staticcall(addr) failed");
        return abi.decode(r, (address));
    }
    function _sc_bool(address target, string memory sig, bytes memory a) internal view returns (bool) {
        (bool ok, bytes memory r) = target.staticcall(bytes.concat(bytes4(keccak256(bytes(sig))), a));
        require(ok, "staticcall(bool) failed");
        return abi.decode(r, (bool));
    }
    function _sc_uint(address target, string memory sig) internal view returns (uint256) {
        (bool ok, bytes memory r) = target.staticcall(abi.encodeWithSignature(sig));
        require(ok, "staticcall(uint) failed");
        return abi.decode(r, (uint256));
    }

    function _assertApplied(Proposal17Activation.Call[] memory cs) internal view {
        for (uint256 i; i < cs.length; ++i) {
            bytes4 s = bytes4(cs[i].data);
            bytes memory tl = _tail(cs[i].data);
            if (s == 0x17a68dd8) {
                address impl = abi.decode(tl, (address));
                assertEq(_sc_addr(cs[i].target, "getImplementation()", ""), impl, "changeImplementation not applied");
            } else if (s == 0x82694b1d) {
                (address m, bool st) = abi.decode(tl, (address, bool));
                assertEq(_sc_bool(cs[i].target, "mapMultisigs(address)", abi.encode(m)), st, "multisig perm not applied");
            } else if (s == 0x05236024) {
                (, , uint256 num, ) = abi.decode(tl, (uint256, uint256, uint256, uint256));
                assertEq(_sc_uint(cs[i].target, "numServicesLimit()"), num, "numServicesLimit not applied");
            } else if (s == 0x0bea55ed) {
                (address[] memory im, bool[] memory st, ) = abi.decode(tl, (address[], bool[], bool));
                for (uint256 j; j < im.length; ++j) {
                    assertEq(_sc_bool(cs[i].target, "mapImplementations(address)", abi.encode(im[j])), st[j], "impl status not applied");
                }
            } else if (s == 0x087f08d4) {
                (address[] memory fs, bool[] memory st) = abi.decode(tl, (address[], bool[]));
                for (uint256 j; j < fs.length; ++j) {
                    assertEq(_sc_bool(cs[i].target, "mapMechFactories(address)", abi.encode(fs[j])), st[j], "factory status not applied");
                }
            } else {
                revert("unknown selector in payload");
            }
        }
    }

    function _opLeg(uint256 cid, address mediator) internal {
        Proposal17Activation.Call[] memory cs = p.chainCalls(cid);
        bytes memory payload = p.packAll(cs);
        address relayer = IMediator(mediator).CDMContractProxyHome();
        vm.mockCall(relayer, abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(TIMELOCK));
        vm.prank(relayer);
        IMediator(mediator).processMessageFromSource(payload);
        _assertApplied(cs);
        console2.log("destination leg applied; chainId", cid, "calls", cs.length);
    }

    // ---- per-chain tests ----
    function test_gnosis() public {
        vm.createSelectFork(vm.envOr("GNOSIS_RPC", string("https://rpc.gnosischain.com")));
        Proposal17Activation.Call[] memory cs = p.chainCalls(100);
        bytes memory payload = p.packAll(cs);
        address amb = IMediator(GNOSIS_MEDIATOR).AMBContractProxyHome();
        vm.mockCall(amb, abi.encodeWithSignature("messageSender()"), abi.encode(TIMELOCK));
        vm.prank(amb);
        IMediator(GNOSIS_MEDIATOR).processMessageFromForeign(payload);
        _assertApplied(cs);
    }

    function test_polygon() public {
        vm.createSelectFork(vm.envOr("POLYGON_RPC", string("https://polygon-bor-rpc.publicnode.com")));
        Proposal17Activation.Call[] memory cs = p.chainCalls(137);
        bytes memory payload = p.packAll(cs);
        address fxChild = IMediator(FX_TUNNEL).fxChild();
        vm.prank(fxChild);
        IMediator(FX_TUNNEL).processMessageFromRoot(1, TIMELOCK, payload);
        _assertApplied(cs);
    }

    function test_optimism() public { vm.createSelectFork(vm.envOr("OPTIMISM_RPC", string("https://optimism.drpc.org"))); _opLeg(10, OPTIMISM_MESSENGER); }
    function test_base() public { vm.createSelectFork(vm.envOr("BASE_RPC", string("https://mainnet.base.org"))); _opLeg(8453, BASE_MESSENGER); }
    function test_celo() public { vm.createSelectFork(vm.envOr("CELO_RPC", string("https://forno.celo.org"))); _opLeg(42220, CELO_MESSENGER); }
    function test_mode() public { vm.createSelectFork(vm.envOr("MODE_RPC", string("https://mainnet.mode.network"))); _opLeg(34443, MODE_MESSENGER); }

    function _retryableLeg(uint256 cid) internal {
        Proposal17Activation.Call[] memory cs = p.chainCalls(cid);
        // Each retryable delivers to its target with the aliased Timelock as msg.sender.
        for (uint256 i; i < cs.length; ++i) {
            vm.prank(TL_ALIAS);
            (bool ok,) = cs[i].target.call(cs[i].data);
            assertTrue(ok, "retryable inner call reverted");
        }
        _assertApplied(cs);
        console2.log("retryable leg applied; chainId", cid, "tickets", cs.length);
    }
    function test_arbitrum() public { vm.createSelectFork(vm.envOr("ARBITRUM_RPC", string("https://arb1.arbitrum.io/rpc"))); _retryableLeg(42161); }
    function test_robinhood() public { vm.createSelectFork(vm.envOr("ROBINHOOD_RPC", string("https://rpc.mainnet.chain.robinhood.com"))); _retryableLeg(4663); }
}
