// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";

/// @title Proposal 18 — protocol maintenance (dispenser pause, guard pause-row, old guard revoke, Celo wrapper revoke)
/// @dev Three Governor actions, all value 0:
///      a) Ethereum, direct: Dispenser(0x5650300f).setPauseState(StakingIncentivesPaused=2).
///      b) Ethereum, direct: GuardCM.setTargetSelectorChainIds — two rows, atomic:
///         row 0: GRANT  the CM pause() on the Dispenser proxy 0x78Bd94F4 (chainId 1);
///         row 1: REVOKE the CM setPauseState(uint8) on the old Dispenser 0x5650300f (chainId 1), so the
///                CM cannot reopen the paused staking-incentive claim path after (a).
///      c) Celo, bridged (OP-stack): ServiceRegistryL2.changeMultisigPermission(legacy wrapper, false).
contract Proposal18 is Script {
    struct Call {
        address target;
        bytes data;
    }

    // ---- L1 targets ----
    address internal constant OLD_DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;
    address internal constant NEW_PROXY     = 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D;
    address internal constant GUARDCM       = 0xC0b146D61e2A2C17E024477E01978D1Fcf598c6B;

    // ---- Celo OP-stack route ----
    address internal constant CELO_L1CDM    = 0x1AC1181fc4e4F877963680587AEAa2C90D7EbB95; // L1 cross-domain messenger
    address internal constant CELO_MESSENGER = 0xC14E191A64a7FB0e5790a8a0B9a58683dFFce04d; // L2 governance mediator
    address internal constant CELO_REGISTRY = 0xE3607b00E75f6405248323A9417ff6b39B244b50; // ServiceRegistryL2
    address internal constant LEGACY_WRAPPER = 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b;

    bytes4  internal constant PAUSE_SELECTOR       = 0x8456cb59; // pause()
    bytes4  internal constant SET_PAUSE_SELECTOR   = 0x63096509; // setPauseState(uint8)
    uint32  internal constant OP_MIN_GAS           = 2_000_000;

    string internal constant DESCRIPTION =
        "Olas protocol maintenance on two chains. On Ethereum the Dispenser at 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0 has its staking-incentive distribution paused (setPauseState to the staking-incentives-paused state); the community-multisig guard GuardCM is granted permission to call the pause entry point of the Dispenser proxy at 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D on Ethereum; and the community-multisig guard's existing permission to call the set-pause-state entry point of the Dispenser at 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0 on Ethereum is revoked, so that the community multisig cannot reopen the paused staking-incentive claim path. On Celo a superseded GnosisSafe service-creation wrapper at 0x63e66d7ad413C01A7b49C7FF4e3Bb765C4E4bd1b has its permission revoked in the service registry. The Ethereum calls are direct Timelock calls; the Celo call is bridged to its governance mediator. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    // Packed buffer tuple the mediator unpacks: (target, uint96 value, uint32 len, data).
    function pk(Call memory c) internal pure returns (bytes memory) {
        return abi.encodePacked(c.target, uint96(0), uint32(c.data.length), c.data);
    }
    function packAll(Call[] memory cs) public pure returns (bytes memory out) {
        for (uint256 i; i < cs.length; ++i) out = bytes.concat(out, pk(cs[i]));
    }
    function opMsg(address messenger, Call[] memory cs) internal pure returns (bytes memory) {
        bytes memory inner = abi.encodeWithSignature("processMessageFromSource(bytes)", packAll(cs));
        return abi.encodeWithSignature("sendMessage(address,bytes,uint32)", messenger, inner, OP_MIN_GAS);
    }

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](3);
        values = new uint256[](3);
        calldatas = new bytes[](3);

        // a) pause the old Dispenser's staking-incentive distribution
        targets[0] = OLD_DISPENSER;
        calldatas[0] = abi.encodeWithSignature("setPauseState(uint8)", uint8(2));

        // b) GuardCM, atomic two-row update:
        //    row 0: GRANT  CM pause() on the new proxy (chainId 1)
        //    row 1: REVOKE CM setPauseState(uint8) on the old Dispenser (chainId 1)
        address[] memory gT = new address[](2); gT[0] = NEW_PROXY;      gT[1] = OLD_DISPENSER;
        bytes4[] memory gS = new bytes4[](2);  gS[0] = PAUSE_SELECTOR;  gS[1] = SET_PAUSE_SELECTOR;
        uint256[] memory gC = new uint256[](2); gC[0] = 1;             gC[1] = 1;
        bool[] memory gB = new bool[](2);       gB[0] = true;          gB[1] = false;
        targets[1] = GUARDCM;
        calldatas[1] = abi.encodeWithSignature(
            "setTargetSelectorChainIds(address[],bytes4[],uint256[],bool[])", gT, gS, gC, gB
        );

        // c) Celo: revoke the legacy wrapper permission, bridged via the OP-stack messenger
        Call[] memory celo = new Call[](1);
        celo[0] = Call(
            CELO_REGISTRY,
            abi.encodeWithSignature("changeMultisigPermission(address,bool)", LEGACY_WRAPPER, false)
        );
        targets[2] = CELO_L1CDM;
        calldatas[2] = opMsg(CELO_MESSENGER, celo);

        description = DESCRIPTION;
    }

    function run() external pure {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal();
        uint256 totalValue;
        for (uint256 i; i < targets.length; ++i) {
            console2.log("---- entry", i);
            console2.log("target", targets[i]);
            console2.log("value ", values[i]);
            console2.logBytes(calldatas[i]);
            totalValue += values[i];
        }
        console2.log("entries:", targets.length);
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
