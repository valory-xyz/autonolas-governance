## Token audits and utilization by Autonolas
The Autonolas `OLAS` contract was partially or fully based on the following sources:
- Full `ERC20` inheritance of [Rari-Capital](https://github.com/Rari-Capital/solmate) implementation
  - Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
  - Audit report: [solmate_audit](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/token/v6-Fixed-Point-Solutions.pdf);
  - Changes between the last audited code and the actual one used by Autonolas clearly state that there were no major changes except for the `permit()` function linearization: [solmate_diff](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/token/SolmateDiffv6.md).
- Adaptation of a couple of functions from [Maple Finance](https://github.com/maple-labs/erc20) `ERC20` token
  - Last known audited version: `756c110ddc3c96c596a52bce43553477a19ee3aa`;
  - Functions added to `OLAS`: `increaseAllowance()`, `decreaseAllowance()`;
  - Changes between the last audited code and the actual one used by Autonolas: [solmate_diff](https://github.com/valory-xyz/autonolas-governance/blob/main/audits/token/MapleDiffv1.md).
- Autonolas continuously gets references and inspiration from [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) set of contracts
  - Last known audited version: `136710cdd4a7b10e93b1774f086a89133f719ebe`.