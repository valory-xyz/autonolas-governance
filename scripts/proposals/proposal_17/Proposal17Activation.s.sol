// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

// PROPOSAL 17 — activation of implementations already deployed and on-chain-checked
// (autonolas-marketplace PR 211, autonolas-registries PR 343). No new contract code.
//
// Routing:
//   - Ethereum: direct Timelock calls.
//   - Gnosis: AMB -> HomeMediator (processMessageFromForeign, packed multicall).
//   - Polygon: FxRoot -> FxGovernorTunnel (packed multicall).
//   - Optimism/Base/Celo/Mode: OP-stack L1CrossDomainMessenger -> OptimismMessenger
//     (processMessageFromSource, packed multicall).
//   - Arbitrum/Robinhood: targets owned by the L2 alias of the L1 Timelock (no mediator),
//     so each call is its own retryable ticket straight to the target.
//
// Per chain the inner calls are:
//   Marketplace:    mktProxy.changeImplementation(newImpl); mktProxy.setMechFactoryStatuses([new..,old..],[true..,false..])
//   ServiceManager: smProxy.changeImplementation(newSM); SR.changeMultisigPermission(newWrapper,true);
//                   SR.changeMultisigPermission(oldWrapper,false)   [enable before disable]
//   StakingToken:   verifier.changeStakingLimits(1e22,2592000,44,3e18); verifier.setImplementationsStatuses([newST,oldST],[true,false],true)
// Mode carries no Marketplace calls (no mech marketplace on Mode).
contract Proposal17Activation is Script {
    struct Call { address target; bytes data; }

    // ---- L1 Timelock + bridge entrypoints ----
    address internal constant TIMELOCK        = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant AMB_FOREIGN     = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e; // Gnosis
    address internal constant FX_ROOT         = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2; // Polygon
    address internal constant OPTIMISM_L1CDM  = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address internal constant BASE_L1CDM      = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa;
    address internal constant CELO_L1CDM      = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95;
    address internal constant MODE_L1CDM      = 0x95bDCA6c8EdEB69C98Bd5bd17660BaCef1298A6f;
    address internal constant ARBITRUM_INBOX  = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address internal constant ROBINHOOD_INBOX = 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D;

    // ---- L2 mediators (owner() of the L2 targets on these chains) ----
    address internal constant GNOSIS_MEDIATOR    = 0x15bd56669F57192a97dF41A2aa8f4403e9491776;
    address internal constant FX_TUNNEL          = 0x9338b5153AE39BB89f50468E608eD9d764B755fD; // Polygon
    address internal constant OPTIMISM_MESSENGER = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c;
    address internal constant BASE_MESSENGER     = 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA;
    address internal constant CELO_MESSENGER     = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d;
    address internal constant MODE_MESSENGER     = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    // Arbitrum/Robinhood: no mediator; retryables go straight to targets, with the aliased Timelock
    // as msg.sender and both refund addresses.
    address internal constant TL_ALIAS = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F;

    // ---- gas params ----
    uint32  internal constant OP_MIN_GAS   = 2_000_000;
    uint256 internal constant AMB_GAS      = 2_000_000;
    uint256 internal constant ARB_GAS_LIMIT       = 300_000;
    uint256 internal constant ARB_MAX_FEE_PER_GAS = 0.05 gwei;
    // Arbitrum/Robinhood retryable submission fee is sized PER CALL from its calldata length at an
    // L1 base-fee ceiling: required = (1400 + 6*len) * baseFee (Nitro AbsInbox). Execution must occur
    // while L1 base fee <= ARB_BASEFEE_CEILING, or either Inbox reverts the whole execution. Excess
    // is refunded to the aliased Timelock on L2.
    uint256 internal constant ARB_BASEFEE_CEILING = 50 gwei;

    // ---- staking limits (live values; only numServices changes 100 -> 44) ----
    uint256 internal constant LIM_MIN_DEP   = 10000000000000000000000; // 1e22
    uint256 internal constant LIM_TIME_EMIS = 2592000;
    uint256 internal constant LIM_NUM_SVC   = 44;
    uint256 internal constant LIM_APY       = 3000000000000000000; // 3e18

    string internal constant DESCRIPTION =
        "Olas protocol maintenance across nine chains, activating implementations already deployed on-chain and independently verified, with no new contract code. On eight chains, each MechMarketplace proxy is upgraded to implementation 1.2.0 and its factory permissions are switched to enable the new native and USDC fixed-price mech factories and disable the superseded ones, OLAS factories remaining disabled. On nine chains, each ServiceManager proxy is upgraded to implementation 1.3.0 and, in each service registry, the new GnosisSafeMultisig wrapper is enabled and superseded wrappers disabled. On nine chains, each staking verifier numServicesLimit is set to 44 with the other limits unchanged, and StakingToken 0.4.0 is allowlisted while the superseded token implementation is disabled, StakingNativeToken excluded. Ethereum calls are direct Timelock calls; Gnosis, Polygon, Optimism, Base, Celo and Mode are bridged to their governance mediators; Arbitrum and Robinhood are delivered as retryable tickets to the targets owned by the Timelock's L2 alias. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    // ================= inner-call encoders =================
    function cImpl(address impl) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("changeImplementation(address)", impl);
    }
    function cPerm(address multisig, bool status) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("changeMultisigPermission(address,bool)", multisig, status);
    }
    function cLimits() internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "changeStakingLimits(uint256,uint256,uint256,uint256)", LIM_MIN_DEP, LIM_TIME_EMIS, LIM_NUM_SVC, LIM_APY);
    }
    function cFactories2(address a0, address a1, bool b0, bool b1) internal pure returns (bytes memory) {
        address[] memory fs = new address[](2); fs[0] = a0; fs[1] = a1;
        bool[] memory ss = new bool[](2); ss[0] = b0; ss[1] = b1;
        return abi.encodeWithSignature("setMechFactoryStatuses(address[],bool[])", fs, ss);
    }
    function cFactories4(address a0, address a1, address a2, address a3) internal pure returns (bytes memory) {
        address[] memory fs = new address[](4); fs[0] = a0; fs[1] = a1; fs[2] = a2; fs[3] = a3;
        bool[] memory ss = new bool[](4); ss[0] = true; ss[1] = true; ss[2] = false; ss[3] = false;
        return abi.encodeWithSignature("setMechFactoryStatuses(address[],bool[])", fs, ss);
    }
    function cStatuses(address newImpl, address oldImpl) internal pure returns (bytes memory) {
        address[] memory im = new address[](2); im[0] = newImpl; im[1] = oldImpl;
        bool[] memory st = new bool[](2); st[0] = true; st[1] = false;
        return abi.encodeWithSignature("setImplementationsStatuses(address[],bool[],bool)", im, st, true);
    }
    function cStatuses3(address newImpl, address old1, address old2) internal pure returns (bytes memory) {
        address[] memory im = new address[](3); im[0] = newImpl; im[1] = old1; im[2] = old2;
        bool[] memory st = new bool[](3); st[0] = true; st[1] = false; st[2] = false;
        return abi.encodeWithSignature("setImplementationsStatuses(address[],bool[],bool)", im, st, true);
    }

    // ================= bridge wrappers =================
    // Packed buffer tuple the mediators unpack: (target, uint96 value, uint32 len, data).
    function pk(Call memory c) internal pure returns (bytes memory) {
        return abi.encodePacked(c.target, uint96(0), uint32(c.data.length), c.data);
    }
    function packAll(Call[] memory cs) public pure returns (bytes memory out) {
        for (uint256 i; i < cs.length; ++i) out = bytes.concat(out, pk(cs[i]));
    }
    function gnosisMsg(Call[] memory cs) internal pure returns (bytes memory) {
        bytes memory inner = abi.encodeWithSignature("processMessageFromForeign(bytes)", packAll(cs));
        return abi.encodeWithSignature("requireToPassMessage(address,bytes,uint256)", GNOSIS_MEDIATOR, inner, AMB_GAS);
    }
    function polygonMsg(Call[] memory cs) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("sendMessageToChild(address,bytes)", FX_TUNNEL, packAll(cs));
    }
    function opMsg(address messenger, Call[] memory cs) internal pure returns (bytes memory) {
        bytes memory inner = abi.encodeWithSignature("processMessageFromSource(bytes)", packAll(cs));
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", messenger, inner, OP_MIN_GAS);
    }
    function arbSubmissionCost(uint256 dataLen) public pure returns (uint256) {
        return (1400 + 6 * dataLen) * ARB_BASEFEE_CEILING;
    }
    function arbTicketValue(Call memory c) public pure returns (uint256) {
        return arbSubmissionCost(c.data.length) + ARB_GAS_LIMIT * ARB_MAX_FEE_PER_GAS;
    }
    function arbTicket(Call memory c) internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "createRetryableTicket(address,uint256,uint256,address,address,uint256,uint256,bytes)",
            c.target, uint256(0), arbSubmissionCost(c.data.length), TL_ALIAS, TL_ALIAS, ARB_GAS_LIMIT, ARB_MAX_FEE_PER_GAS, c.data);
    }

    // ================= per-chain call lists =================
    // Marketplace: returns 2 calls (changeImpl + setMechFactoryStatuses). hasUsdc=false -> 2-factory switch.
    function mCalls(address mkt, address newImpl, bytes memory factorySwitch) internal pure returns (Call[] memory cs) {
        cs = new Call[](2);
        cs[0] = Call(mkt, cImpl(newImpl));
        cs[1] = Call(mkt, factorySwitch);
    }
    // ServiceManager: 3 calls.
    function rCalls(address smProxy, address newSM, address sr, address newW, address oldW)
        internal pure returns (Call[] memory cs)
    {
        cs = new Call[](3);
        cs[0] = Call(smProxy, cImpl(newSM));
        cs[1] = Call(sr, cPerm(newW, true));
        cs[2] = Call(sr, cPerm(oldW, false));
    }
    // StakingToken: 2 calls.
    function sCalls(address verifier, address newST, address oldST) internal pure returns (Call[] memory cs) {
        cs = new Call[](2);
        cs[0] = Call(verifier, cLimits());
        cs[1] = Call(verifier, cStatuses(newST, oldST));
    }
    function sCalls3(address verifier, address newST, address old1, address old2) internal pure returns (Call[] memory cs) {
        cs = new Call[](2);
        cs[0] = Call(verifier, cLimits());
        cs[1] = Call(verifier, cStatuses3(newST, old1, old2));
    }

    function concat(Call[] memory a, Call[] memory b) internal pure returns (Call[] memory out) {
        out = new Call[](a.length + b.length);
        uint256 k;
        for (uint256 i; i < a.length; ++i) out[k++] = a[i];
        for (uint256 i; i < b.length; ++i) out[k++] = b[i];
    }
    function concat3(Call[] memory a, Call[] memory b, Call[] memory c) internal pure returns (Call[] memory) {
        return concat(concat(a, b), c);
    }

    // ================= per-chain call lists (L2) =================
    function callsGnosis() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0x735FAAb1c4Ec41128c367AFb5c3baC73509f70bB, 0x2880DF3934358d3B644928fe92D3ecd0dF87808C,
                   cFactories2(0x5270c0797a9D0c59163cF570129E5808BE7927FA, 0x8b299c20F87e3fcBfF0e1B86dC0acC06AB6993EF, true, false)),
            rCalls(0x068a4f0946cF8c7f9C1B58a3b5243Ac8843bf473, 0x5DdD34c367EF3BaA8aBEDF70FFe7f617A46924e7,
                   0x9338b5153AE39BB89f50468E608eD9d764B755fD, 0x3835C338Fe82abEc60DB21dB2f22E251A26D071F, 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE),
            sCalls(0x1D59DadE4FAeA7771eC7221420012d413175404C, 0x5777C44C8926085C2d7cF33735F57f2f05A90a1a, 0xEa00be6690a871827fAfD705440D20dd75e67AB1));
    }
    function callsPolygon() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0x343F2B005cF6D70bA610CD9F1F1927049414B582, 0x67722c823010CEb4BED5325fE109196C0f67D053,
                   cFactories4(0x40dABcF2DEEc7241749B320cbC5ca69544a90d68, 0x749cdf4bF2e55269b3d1bC4b4408e34689c96B67, 0x87f89F94033305791B6269AE2F9cF4e09983E56e, 0x85899f9d8C058A5BBBaF344ea0f0b63c0CcBe851)),
            rCalls(0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0, 0x0Bb2E75a97A0d0A13A97BC7dab1207a400EEff34,
                   0xE3607b00E75f6405248323A9417ff6b39B244b50, 0x87E6a97bD97D41904B1125A014B16bec50C6A89D, 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44),
            sCalls(0x8Bc0a5c5B1612A16983B01ecd7ae130E728390CB, 0x980b47e2B78403fBeDd59fbd6C7f8bF93d2E6B10, 0x4aba1Cf7a39a51D75cBa789f5f21cf4882162519));
    }
    function callsOptimism() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461, 0x7beD01f8482fF686F025628e7780ca6C1f0559fc,
                   cFactories4(0xaaFBeef195BDAb1Bb6f3Dc9cEbA875Cd72499230, 0xf78b3C22A204Da5d9a0B080C5D3d695AF4918886, 0xf76953444C35F1FcE2F6CA1b167173357d3F5C17, 0x93111f6C267068A5d7356114D61d0f09bFD53a54)),
            rCalls(0xA5C7FbCCFf28441b7d250412b0Fb87AA1c8b14AD, 0x6F121552765424f0B2331B541C0938480cA314Db,
                   0x3d77596beb0f130a4415df3D2D8232B3d3D31e44, 0xe15Eb6549484F7f8F45D0707EA05AA39DBDd65Ce, 0x5953f21495BD9aF1D78e87bb42AcCAA55C1e896C),
            sCalls(0x526E064cB694E8f5B7DB299158e17F33055B3943, 0x28C1edC7CEd549F7f80B732fDC19f0370160707d, 0x63C2c53c09dE534Dd3bc0b7771bf976070936bAC));
    }
    function callsBase() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0xf24eE42edA0fc9b33B7D41B06Ee8ccD2Ef7C5020, 0xE8712Eb720345A6eC07eC85016e367104c1524BB,
                   cFactories4(0xf8a8C985f46Ab6204e6A40845e73a6119f0458ED, 0x17D8B863F6c4601d67A87FDa04D53849c5F9Ce00, 0x2E008211f34b25A7d7c102403c6C2C3B665a1abe, 0x5B70A66fe68c4c86FFd724B58cc56049c70e9D3D)),
            rCalls(0x1262136cac6a06A782DC94eb3a3dF0b4d09FF6A6, 0x7c604abaDc3A885F4f47Eb25B44D26CdF16258DA,
                   0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE, 0x25c980328762a03F70c2649ef4Be691b811B690A, 0x22bE6fDcd3e29851B29b512F714C328A00A96B83),
            sCalls(0x10c5525F77F13b28f42c5626240c001c2D57CAd4, 0x67C48a1cdCBCC311CA6484560F8c5066F3655b6e, 0xEB5638eefE289691EcE01943f768EDBF96258a80));
    }
    function callsCelo() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0x17d96ba4532fe91809326092fE4D5606A7B7a0d8, 0x5C50ebc17d002A4484585C8fbf62f51953493c0B,
                   cFactories4(0x0a9a74274b1C30845aF98683Ca7F843795f6DFA6, 0x16184FcF1940dFb8aA5Eba7E1effefAd49c733F5, 0xDd1252c5a75be568B5E6e50bA542680b38dbd68f, 0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0)),
            rCalls(0x84B4DA67B37B1EA1dea9c7044042C1d2297b80a0, 0x7beD01f8482fF686F025628e7780ca6C1f0559fc,
                   0xE3607b00E75f6405248323A9417ff6b39B244b50, 0xaaFBeef195BDAb1Bb6f3Dc9cEbA875Cd72499230, 0xD421f433e36465B3e558B1121F584ac09Fc33DF8),
            sCalls3(0x4aba1Cf7a39a51D75cBa789f5f21cf4882162519, 0xf78b3C22A204Da5d9a0B080C5D3d695AF4918886, 0xe1E1B286EbE95b39F785d8069f2248ae9C41b7a9, 0xd2ff4Cf0927c3cFbF3BB27391044dBaf6f4ca7b9));
    }
    function callsMode() internal pure returns (Call[] memory) { // no marketplace on Mode
        return concat(
            rCalls(0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d, 0x379451B13e4900C7005Bf57467770b2EE4e62a86,
                   0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE, 0x22bE6fDcd3e29851B29b512F714C328A00A96B83, 0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac),
            sCalls(0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c, 0x5add592ce0a1B5DceCebB5Dcac086Cd9F9e3eA5C, 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA));
    }
    function callsArbitrum() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0xf76953444C35F1FcE2F6CA1b167173357d3F5C17, 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300,
                   cFactories4(0xa0DA53447C0f6C4987964d8463da7e6628B30f82, 0x1521918961bDBC9Ed4C67a7103D5999e4130E6CB, 0x4Cd816ce806FF1003ee459158A093F02AbF042a8, 0x694e62BDF7Ff510A4EE66662cf4866A961a31653)),
            rCalls(0xD421f433e36465B3e558B1121F584ac09Fc33DF8, 0x52A043bcebdB2f939BaEF2E8b6F01652290eAB3f,
                   0xE3607b00E75f6405248323A9417ff6b39B244b50, 0xeED0000fE94d7cfeF4Dc0CA86a223f0F603A61B8, 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b),
            sCalls(0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68, 0x887A511e3DfE4dDa77c0b1783c01d9920351A83D, 0x04b0007b2aFb398015B76e5f22993a1fddF83644));
    }
    function callsRobinhood() internal pure returns (Call[] memory) {
        Call[] memory adapter = new Call[](1);
        // revoke the deprecated same-address Safe adapter on the Robinhood service registry
        adapter[0] = Call(0xE3607b00E75f6405248323A9417ff6b39B244b50, cPerm(0xFbBEc0C8b13B38a9aC0499694A69a10204c5E2aB, false));
        return concat(adapter, concat3(
            mCalls(0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8, 0xA5C7FbCCFf28441b7d250412b0Fb87AA1c8b14AD,
                   cFactories4(0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d, 0x24F792D51b398928459Dfbb4181bDb4D5d2CD472, 0x04b0007b2aFb398015B76e5f22993a1fddF83644, 0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68)),
            rCalls(0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b, 0x379451B13e4900C7005Bf57467770b2EE4e62a86,
                   0xE3607b00E75f6405248323A9417ff6b39B244b50, 0x22bE6fDcd3e29851B29b512F714C328A00A96B83, 0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac),
            sCalls(0x75D529FAe220bC8db714F0202193726b46881B76, 0x5add592ce0a1B5DceCebB5Dcac086Cd9F9e3eA5C, 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c)));
    }

    // Ethereum L1 direct calls (7).
    function callsEthereum() internal pure returns (Call[] memory) {
        return concat3(
            mCalls(0x3d6494CE09a9f40c0B5a92BdBD7c7A9b0e3912b1, 0x43D9DeBe4a539334462d1e96068918B8B19650d3,
                   cFactories4(0xf5648BB207ce909D76C219c709433d3Ac05E8B86, 0x1F7f307Ecd0ea3778dE3Eb961dEc5A0f814AFCcf, 0x3515a36AF270070635Fa3E957e006aaF6078e658, 0xF95BfBBA428dfb454Cd59C9c2d309bd6452d12A8)),
            rCalls(0x94a1892D91c05D0C61c3f49F42205D2285b914c9, 0x20F1586730261c5842715Ad3c5563Ecef19E0B2b,
                   0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA, 0x48BE9146eBe74Af8f9BbC42A0EB68B484AC8Df31, 0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461),
            sCalls(0x4503b79d468e81Ad2d4bd6Db991810da269bA777, 0x3A8867A5A31c5E26e6b8c740c1E1Aa920802d4BA, 0x0Dc23eEf3bC64CF3cbd8f9329B57AE4C4f28d5d2));
    }

    // Per-chain inner call list (for destination-leg tests). Mediator chains pack these into one
    // message; Arbitrum/Robinhood deliver each as its own retryable to the target.
    function chainCalls(uint256 chainId) public pure returns (Call[] memory) {
        if (chainId == 100) return callsGnosis();
        if (chainId == 137) return callsPolygon();
        if (chainId == 10) return callsOptimism();
        if (chainId == 8453) return callsBase();
        if (chainId == 42220) return callsCelo();
        if (chainId == 34443) return callsMode();
        if (chainId == 42161) return callsArbitrum();
        if (chainId == 4663) return callsRobinhood();
        revert("unknown chain");
    }

    // ================= assembly =================
    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        Call[] memory eth = callsEthereum();            // 7 direct
        Call[] memory arb = callsArbitrum();            // 7 retryables
        Call[] memory rh  = callsRobinhood();           // 7 retryables
        uint256 n = eth.length + 6 + arb.length + rh.length; // 7 + 6 mediator + 7 + 8 = 28
        targets = new address[](n);
        values = new uint256[](n);
        calldatas = new bytes[](n);
        uint256 k;

        // [0..6] Ethereum direct
        for (uint256 i; i < eth.length; ++i) { targets[k] = eth[i].target; calldatas[k] = eth[i].data; ++k; }

        // mediator chains — one message each
        targets[k] = AMB_FOREIGN;    calldatas[k] = gnosisMsg(callsGnosis());                 ++k;
        targets[k] = FX_ROOT;        calldatas[k] = polygonMsg(callsPolygon());               ++k;
        targets[k] = OPTIMISM_L1CDM; calldatas[k] = opMsg(OPTIMISM_MESSENGER, callsOptimism()); ++k;
        targets[k] = BASE_L1CDM;     calldatas[k] = opMsg(BASE_MESSENGER, callsBase());        ++k;
        targets[k] = CELO_L1CDM;     calldatas[k] = opMsg(CELO_MESSENGER, callsCelo());        ++k;
        targets[k] = MODE_L1CDM;     calldatas[k] = opMsg(MODE_MESSENGER, callsMode());        ++k;

        // Arbitrum retryables (value-carrying; per-call submission fee)
        for (uint256 i; i < arb.length; ++i) { targets[k] = ARBITRUM_INBOX; values[k] = arbTicketValue(arb[i]); calldatas[k] = arbTicket(arb[i]); ++k; }
        // Robinhood retryables
        for (uint256 i; i < rh.length; ++i) { targets[k] = ROBINHOOD_INBOX; values[k] = arbTicketValue(rh[i]); calldatas[k] = arbTicket(rh[i]); ++k; }

        description = DESCRIPTION;
    }

    function run() external pure {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = buildProposal();
        console2.log("entries:", targets.length);
        uint256 totalValue;
        for (uint256 i; i < targets.length; ++i) {
            console2.log("---- entry", i);
            console2.log("target", targets[i]);
            console2.log("value ", values[i]);
            console2.logBytes(calldatas[i]);
            totalValue += values[i];
        }
        console2.log("total ETH value (wei):", totalValue);
        bytes32 descHash = keccak256(bytes(description));
        console2.log("descriptionHash:");
        console2.logBytes32(descHash);
        bytes32 pid = keccak256(abi.encode(targets, values, calldatas, descHash));
        console2.log("proposalId (hex):");
        console2.logBytes32(pid);
        console2.log("proposalId (uint):", uint256(pid));
    }
}
