// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

/// @title Proposal11Builder - Single source of truth for the proposal 11 activation governance proposal.
/// @dev Builds the (targets, values, calldatas, description) for the combined activation vote:
///        A) migrate Timelock roles old governor -> new governor
///        B) configure bridge mediators on the new GuardCM (Mode excluded)
///        C) configure the CM target-selector allowlist on the new GuardCM (16 entries)
///        D) swap the CM guard to the new GuardCM via the Timelock Safe-module
///        E) set new Celo BalanceTrackers on the MechMarketplaceProxy (bridged, OP-stack)
///        F) upgrade the Tokenomics implementation behind TokenomicsProxy
///      All addresses verified on-chain (see docs/activation_checklist_proposal_11.md). The proposal is
///      submitted through whichever governor currently holds Timelock roles (today: the OLD governor),
///      and every call below is executed BY the Timelock.
abstract contract Proposal11Builder {
    // ---- Core ----
    address internal constant TIMELOCK   = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;
    address internal constant OLD_GOV    = 0x8E84B5055492901988B831817e4Ace5275A3b401;
    address internal constant NEW_GOV    = 0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6;
    address internal constant NEW_GUARD  = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;
    address internal constant CM         = 0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570;

    // ---- Timelock roles (OZ TimelockController) ----
    bytes32 internal constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 internal constant PROPOSER_ROLE       = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE       = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE      = keccak256("CANCELLER_ROLE");

    // ---- B: bridge mediators (L1 entry / L2 verifier / L2 mediator) ----
    address internal constant AMB_L1     = 0x4C36d2919e407f0Cc2Ee3c993ccF8ac26d9CE64e; // Gnosis
    address internal constant FXROOT_L1  = 0xfe5e5D361b2ad62c541bAb87C45a0B9B018389a2; // Polygon
    address internal constant INBOX_L1   = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f; // Arbitrum
    address internal constant OP_L1CDM   = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1; // Optimism
    address internal constant BASE_L1CDM = 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa; // Base
    address internal constant CELO_L1CDM = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95; // Celo

    address internal constant VERIFIER_GNOSIS   = 0xDc871b7833932D45023755C9De3786060a934c48;
    address internal constant VERIFIER_POLYGON  = 0x133A6d318FA0C9413A70C149E7f630015044Dec3;
    address internal constant VERIFIER_ARBITRUM = 0x0F33636698F6607B2FDdC1e857788535914C44d4;
    address internal constant VERIFIER_OPTIMISM = 0xdCAFcCcC7bA0b7185A472d9d068FDe0AF4313Fb5; // OP/Base/Celo

    address internal constant HOME_MEDIATOR_L2 = 0x15bd56669F57192a97dF41A2aa8f4403e9491776; // Gnosis
    address internal constant FX_TUNNEL_L2     = 0x9338b5153AE39BB89f50468E608eD9d764B755fD; // Polygon
    address internal constant ARB_MEDIATOR_L2  = 0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F; // Arbitrum
    address internal constant OP_MESSENGER_L2  = 0x87c511c8aE3fAF0063b3F3CF9C6ab96c4AA5C60c; // Optimism
    address internal constant BASE_MESSENGER_L2= 0xE49CB081e8d96920C38aA7AB90cb0294ab4Bc8EA; // Base
    address internal constant CELO_MESSENGER_L2= 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d; // Celo

    // ---- C: allowlist targets ----
    address internal constant TREASURY      = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant DEPOSITORY    = 0xfF8697d8d2998d6AA2e09B405795C6F4BEeB0C81; // LIVE (Treasury.depository())
    address internal constant SRTU_L1       = 0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA;
    // L2 ServiceRegistryL2 / ServiceRegistryTokenUtility (verified drainer()/owner() == bridgeMediator)
    address internal constant SRL2_GNOSIS   = 0x9338b5153AE39BB89f50468E608eD9d764B755fD;
    address internal constant SRTU_GNOSIS   = 0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8;
    address internal constant SRL2_POLYGON  = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRTU_POLYGON  = 0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8;
    address internal constant SRL2_ARBITRUM = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRTU_ARBITRUM = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;
    address internal constant SRL2_OPTIMISM = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;
    address internal constant SRTU_OPTIMISM = 0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac;
    address internal constant SRL2_BASE     = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE; // CREATE2 (distinct contract on Base)
    address internal constant SRTU_BASE     = 0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5; // CREATE2 (distinct contract on Base)
    address internal constant SRL2_CELO     = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal constant SRTU_CELO     = 0x3d77596beb0f130a4415df3D2D8232B3d3D31e44;

    // ---- C: selectors ----
    bytes4 internal constant SEL_PAUSE            = 0x8456cb59; // pause()
    bytes4 internal constant SEL_DRAIN_SLASHED    = 0x8f202bf9; // drainServiceSlashedFunds()
    bytes4 internal constant SEL_CLOSE            = 0x58d3ec6a; // close(uint256[])
    bytes4 internal constant SEL_DRAIN_ADDRESS    = 0xece53132; // drain(address)
    bytes4 internal constant SEL_DRAIN            = 0x9890220b; // drain()

    // ---- chain ids ----
    uint256 internal constant CID_MAINNET  = 1;
    uint256 internal constant CID_GNOSIS   = 100;
    uint256 internal constant CID_POLYGON  = 137;
    uint256 internal constant CID_ARBITRUM = 42161;
    uint256 internal constant CID_OPTIMISM = 10;
    uint256 internal constant CID_BASE     = 8453;
    uint256 internal constant CID_CELO     = 42220;

    // ---- E: Celo marketplace ----
    address internal constant CELO_MECH_PROXY = 0x17d96ba4532fe91809326092fE4D5606A7B7a0d8;
    bytes32 internal constant PT_NATIVE = 0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1;
    bytes32 internal constant PT_OLAS   = 0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9;
    bytes32 internal constant PT_USDC   = 0x6406bb5f31a732f898e1ce9fdd988a80a808d36ab5d9a4a4805a8be8d197d5e3;
    address internal constant CELO_BT_NATIVE = 0x2E008211f34b25A7d7c102403c6C2C3B665a1abe;
    address internal constant CELO_BT_OLAS   = 0xB3921F8D8215603f0Bd521341Ac45eA8f2d274c1;
    address internal constant CELO_BT_USDC   = 0x97371B1C0cDA1D04dFc43DFb50a04645b7Bc9BEe;
    uint32  internal constant CELO_MIN_GAS   = 2_000_000;

    // ---- F: tokenomics ----
    address internal constant TOKENOMICS_PROXY = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address internal constant TOKENOMICS_NEW_IMPL = 0xaeeC8bC8E5Fe28BC4dF2e9586b222924b8a0d5e9;

    // Canonical proposal description. MUST match scripts/proposals/proposal_11/description.txt
    // byte-for-byte: proposalId (shown in proposal_11.html) is keccak over (targets,values,calldatas,
    // keccak(description)). Single line, no embedded newlines, no trailing newline.
    string internal constant DESCRIPTION =
        "Olas Governance and Community Multisig (CM) Guard activation. This proposal completes the on-chain adoption of the updated GovernorOLAS and GuardCM deployed in PR #199, and bundles two related protocol upgrades. It: (A) migrates the Timelock ADMIN, PROPOSER, EXECUTOR and CANCELLER roles from the previous GovernorOLAS (0x8E84B5055492901988B831817e4Ace5275A3b401) to the newly deployed GovernorOLAS (0x060D0CBdDFb0498d610E2EF55C01516B5B1251E6); (B) configures the new GuardCM (0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B) bridge mediators and L2 payload verifiers for Gnosis, Polygon, Arbitrum, Optimism, Base and Celo; (C) sets the new GuardCM allowlist of Community Multisig target/selector/chainId combinations, namely Treasury pause() and drainServiceSlashedFunds(), Depository close(uint256[]), and ServiceRegistry/ServiceRegistryTokenUtility drain functions on Ethereum and across the supported L2 networks; (D) swaps the Community Multisig guard to the new GuardCM via the Timelock Safe-module; (E) registers the newly deployed Celo BalanceTracker contracts on the Celo MechMarketplace; and (F) upgrades the Tokenomics implementation behind the TokenomicsProxy to version 1.4.3. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    /// @dev Builds the full activation proposal.
    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](16);
        values = new uint256[](16); // all zero
        calldatas = new bytes[](16);
        uint256 k;

        // ---- A) role migration (8) : target = Timelock ----
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("grantRole(bytes32,address)", TIMELOCK_ADMIN_ROLE, NEW_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, NEW_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("grantRole(bytes32,address)", EXECUTOR_ROLE, NEW_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("grantRole(bytes32,address)", CANCELLER_ROLE, NEW_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("revokeRole(bytes32,address)", TIMELOCK_ADMIN_ROLE, OLD_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("revokeRole(bytes32,address)", PROPOSER_ROLE, OLD_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("revokeRole(bytes32,address)", EXECUTOR_ROLE, OLD_GOV);
        targets[k] = TIMELOCK; calldatas[k++] = abi.encodeWithSignature("revokeRole(bytes32,address)", CANCELLER_ROLE, OLD_GOV);

        // ---- B) bridge mediators (4) : target = new GuardCM ----
        targets[k] = NEW_GUARD; calldatas[k++] = _bridge(AMB_L1, VERIFIER_GNOSIS, CID_GNOSIS, HOME_MEDIATOR_L2);
        targets[k] = NEW_GUARD; calldatas[k++] = _bridge(FXROOT_L1, VERIFIER_POLYGON, CID_POLYGON, FX_TUNNEL_L2);
        targets[k] = NEW_GUARD; calldatas[k++] = _bridge(INBOX_L1, VERIFIER_ARBITRUM, CID_ARBITRUM, ARB_MEDIATOR_L2);
        targets[k] = NEW_GUARD; calldatas[k++] = _bridgeOpFamily();

        // ---- C) target-selector allowlist (1) : target = new GuardCM ----
        targets[k] = NEW_GUARD; calldatas[k++] = _allowlist();

        // ---- D) swap CM guard via Timelock module (1) : target = CM ----
        bytes memory setGuard = abi.encodeWithSignature("setGuard(address)", NEW_GUARD);
        targets[k] = CM; calldatas[k++] = abi.encodeWithSignature(
            "execTransactionFromModule(address,uint256,bytes,uint8)", CM, uint256(0), setGuard, uint8(0) /*Call*/);

        // ---- E) set Celo BalanceTrackers (1, bridged) : target = Celo L1CrossDomainMessenger ----
        targets[k] = CELO_L1CDM; calldatas[k++] = _celoTrackers();

        // ---- F) Tokenomics implementation upgrade (1) : target = TokenomicsProxy ----
        targets[k] = TOKENOMICS_PROXY; calldatas[k++] =
            abi.encodeWithSignature("changeTokenomicsImplementation(address)", TOKENOMICS_NEW_IMPL);

        require(k == 16, "length mismatch");
        // NOTE: must match scripts/proposals/proposal_11/description.txt byte-for-byte
        // (the proposalId in proposal_11.html is computed from this exact string).
        description = DESCRIPTION;
    }

    function _bridge(address l1, address verifier, uint256 chainId, address l2) internal pure returns (bytes memory) {
        address[] memory l1s = new address[](1); l1s[0] = l1;
        address[] memory vs = new address[](1); vs[0] = verifier;
        uint256[] memory cids = new uint256[](1); cids[0] = chainId;
        address[] memory l2s = new address[](1); l2s[0] = l2;
        return abi.encodeWithSignature(
            "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])", l1s, vs, cids, l2s);
    }

    function _bridgeOpFamily() internal pure returns (bytes memory) {
        address[] memory l1s = new address[](3); l1s[0] = OP_L1CDM; l1s[1] = BASE_L1CDM; l1s[2] = CELO_L1CDM;
        address[] memory vs = new address[](3); vs[0] = VERIFIER_OPTIMISM; vs[1] = VERIFIER_OPTIMISM; vs[2] = VERIFIER_OPTIMISM;
        uint256[] memory cids = new uint256[](3); cids[0] = CID_OPTIMISM; cids[1] = CID_BASE; cids[2] = CID_CELO;
        address[] memory l2s = new address[](3); l2s[0] = OP_MESSENGER_L2; l2s[1] = BASE_MESSENGER_L2; l2s[2] = CELO_MESSENGER_L2;
        return abi.encodeWithSignature(
            "setBridgeMediatorL1BridgeParams(address[],address[],uint256[],address[])", l1s, vs, cids, l2s);
    }

    function _allowlist() internal pure returns (bytes memory) {
        address[] memory t = new address[](16);
        bytes4[] memory s = new bytes4[](16);
        uint256[] memory c = new uint256[](16);
        bool[] memory st = new bool[](16);
        uint256 i;
        // Mainnet (4)
        t[i] = TREASURY;   s[i] = SEL_PAUSE;         c[i] = CID_MAINNET;  st[i++] = true;
        t[i] = TREASURY;   s[i] = SEL_DRAIN_SLASHED; c[i] = CID_MAINNET;  st[i++] = true;
        t[i] = DEPOSITORY; s[i] = SEL_CLOSE;         c[i] = CID_MAINNET;  st[i++] = true;
        t[i] = SRTU_L1;    s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_MAINNET;  st[i++] = true;
        // L2 drain matrix (12)
        t[i] = SRL2_GNOSIS;   s[i] = SEL_DRAIN;         c[i] = CID_GNOSIS;   st[i++] = true;
        t[i] = SRTU_GNOSIS;   s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_GNOSIS;   st[i++] = true;
        t[i] = SRL2_POLYGON;  s[i] = SEL_DRAIN;         c[i] = CID_POLYGON;  st[i++] = true;
        t[i] = SRTU_POLYGON;  s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_POLYGON;  st[i++] = true;
        t[i] = SRL2_ARBITRUM; s[i] = SEL_DRAIN;         c[i] = CID_ARBITRUM; st[i++] = true;
        t[i] = SRTU_ARBITRUM; s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_ARBITRUM; st[i++] = true;
        t[i] = SRL2_OPTIMISM; s[i] = SEL_DRAIN;         c[i] = CID_OPTIMISM; st[i++] = true;
        t[i] = SRTU_OPTIMISM; s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_OPTIMISM; st[i++] = true;
        t[i] = SRL2_BASE;     s[i] = SEL_DRAIN;         c[i] = CID_BASE;     st[i++] = true;
        t[i] = SRTU_BASE;     s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_BASE;     st[i++] = true;
        t[i] = SRL2_CELO;     s[i] = SEL_DRAIN;         c[i] = CID_CELO;     st[i++] = true;
        t[i] = SRTU_CELO;     s[i] = SEL_DRAIN_ADDRESS; c[i] = CID_CELO;     st[i++] = true;
        require(i == 16, "allowlist length");
        return abi.encodeWithSignature(
            "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])", t, s, c, st);
    }

    function _celoTrackers() internal pure returns (bytes memory) {
        bytes32[] memory pts = new bytes32[](3); pts[0] = PT_NATIVE; pts[1] = PT_OLAS; pts[2] = PT_USDC;
        address[] memory bts = new address[](3); bts[0] = CELO_BT_NATIVE; bts[1] = CELO_BT_OLAS; bts[2] = CELO_BT_USDC;
        bytes memory inner = abi.encodeWithSignature("setPaymentTypeBalanceTrackers(bytes32[],address[])", pts, bts);
        // BridgeMessenger packing: target(20) | value(uint96,12) | payloadLength(uint32,4) | payload
        bytes memory packed = abi.encodePacked(CELO_MECH_PROXY, uint96(0), uint32(inner.length), inner);
        bytes memory l2call = abi.encodeWithSignature("processMessageFromSource(bytes)", packed);
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", CELO_MESSENGER_L2, l2call, CELO_MIN_GAS);
    }
}

/// @notice Run: forge script scripts/proposals/proposal_11/Proposal11Activation.s.sol:Proposal11Activation
///         (no broadcast — prints the proposal arrays to copy into the governor `propose(...)` call).
contract Proposal11Activation is Script, Proposal11Builder {
    function run() external view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();

        console2.log("=== Proposal 11 activation ===");
        console2.log("entries:", targets.length);
        for (uint256 i; i < targets.length; ++i) {
            console2.log("--- index", i, "---");
            console2.log("target  :", targets[i]);
            console2.log("value   :", values[i]);
            console2.log("calldata:");
            console2.logBytes(calldatas[i]);
        }
        console2.log("description:");
        console2.log(description);
    }
}
