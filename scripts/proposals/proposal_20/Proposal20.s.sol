// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";

/// @title Proposal 20 — protocol maintenance (Dispenser manager update + unpause)
/// @dev Three Governor actions on Ethereum, all value 0, all direct Timelock calls:
///      a) Tokenomics.changeManagers(0, 0, DISPENSER_PROXY) — set the Tokenomics dispenser manager to the
///         Dispenser proxy 0x78Bd94F4 (zero args leave treasury/depository unchanged).
///      b) Treasury.changeManagers(0, 0, DISPENSER_PROXY) — set the Treasury dispenser manager to the same
///         proxy (zero args leave tokenomics/depository unchanged); this authorises the proxy for withdrawals.
///      c) DispenserProxy.setPauseState(Unpaused=0) — unpause the Dispenser proxy.
contract Proposal20 is Script {
    // ---- L1 targets ----
    address internal constant TOKENOMICS      = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address internal constant TREASURY        = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant DISPENSER_PROXY = 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D;

    string internal constant DESCRIPTION =
        "Olas protocol maintenance on Ethereum. The dispenser manager of the Tokenomics contract at 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300 is set to the Dispenser proxy at 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D; the dispenser manager of the Treasury contract at 0xa0DA53447C0f6C4987964d8463da7e6628B30f82 is set to the same Dispenser proxy; and that Dispenser proxy has its pause state set to unpaused. All three are direct Timelock calls on Ethereum, each carrying no value. In accordance with Autonolas DAO Constitution at ipfs://bafybeibrhz6hnxsxcbv7dkzerq4chssotexb276pidzwclbytzj7m4t47u";

    function buildProposal()
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](3);
        values = new uint256[](3);
        calldatas = new bytes[](3);

        // a) Tokenomics: set dispenser manager (treasury + depository args left as zero -> unchanged)
        targets[0] = TOKENOMICS;
        calldatas[0] = abi.encodeWithSignature(
            "changeManagers(address,address,address)", address(0), address(0), DISPENSER_PROXY
        );

        // b) Treasury: set dispenser manager (tokenomics + depository args left as zero -> unchanged)
        targets[1] = TREASURY;
        calldatas[1] = abi.encodeWithSignature(
            "changeManagers(address,address,address)", address(0), address(0), DISPENSER_PROXY
        );

        // c) Dispenser proxy: unpause (Unpaused = 0)
        targets[2] = DISPENSER_PROXY;
        calldatas[2] = abi.encodeWithSignature("setPauseState(uint8)", uint8(0));

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
