# Autonolas governance ABIs

Most of these ABIs were obtained with 1000000 optimization passes.

An artifact here is also the reference `scripts/audit_chains/audit_contracts_setup.js` compares
deployed bytecode against, so **an artifact must be built the way its contract was actually
deployed**, not to a house convention. Where the two disagree the deployment wins.

`GuardCM` and `GovernorOLAS` are built with the repo's own `hardhat.config.js` settings — solc
0.8.30, `evm_version = prague`, **200 optimization passes** — because that is what produced the
contracts activated by proposal 11 (`0xC0b146D6` and `0x060D0CBd`). Rebuilding them at 1000000
passes, or at the 750 this file previously recorded for `GovernorOLAS`, yields 10613 B and 21171 B
against the 8331 B and 20479 B that are deployed.

`VoteWeighting` has two entries. `0.8.25` is the live contract at `0x95418b46`; `0.8.30` is the
2-arg-constructor build prepared for the pending redeploy. Keep both until that redeploy lands, then
repoint `docs/configuration.json` and drop the 0.8.25 one.
