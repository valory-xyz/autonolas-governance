/*global process*/

const { ethers } = require("hardhat");

function convertAddressToBytes32(account) {
  return ("0x" + "0".repeat(24) + account.slice(2)).toLowerCase();
}

// to run: "npx hardhat run scripts/script.js --network local"
async function main() {
  const oneWeek = 7 * 86400;
  const oneYear = 365 * 86400;
  const OLASBalance = ethers.utils.parseEther("100");

  const olasAddress = "0x0001A500A6B18995B03f44bb040A5fFc28E45CB0";
  const veolasAddress = "0x7e01A500805f8A52Fad229b3015AD130A332B7b3";

  const OLAS = await ethers.getContractFactory("OLAS");
  let olas;

  // deploy OLAS if not deployed
  if ((await ethers.provider.getCode(olasAddress)) !== "0x") {
    olas = await OLAS.attach(olasAddress);
  } else {
    olas = await OLAS.deploy();
    await olas.deployed();
  }

  // deploy veOLAS if not deployed
  const VE = await ethers.getContractFactory("veOLAS");
  let ve;
  if ((await ethers.provider.getCode(veolasAddress)) !== "0x") {
    ve = await VE.attach(veolasAddress);
  } else {
    ve = await VE.deploy(olas.address, "name", "symbol");
    await ve.deployed();
  }

  const signers = await ethers.getSigners();

  const VoteWeighting = await ethers.getContractFactory("VoteWeighting");
  const vw = await VoteWeighting.deploy(ve.address);
  await vw.deployed();

  const contracts = [
    { address: "0x7248d855a3d4d17c32Eb0D996A528f7520d2F4A3", chainId: 1 },
    { address: "0xe26AE1Aa2bc8d499014cFcb134beEf371a89016F", chainId: 1 },
    { address: "0x14D28BfCC328e12732551EFbb771384261761aC6", chainId: 1 },
    { address: "0xeBB8987A0767A975590e8351CA704B76d951c512", chainId: 100 },
    { address: "0x69552d9Fdb3E0121CB4C08D209DEc11ad5428f62", chainId: 100 },
    { address: "0xe6bB3fdf84CBA2b7f6A3e7ABD7F8098c628568a1", chainId: 100 },
    { address: "0x6158Ffa88564be2CEAbcFdD83594f691bbcF13E8", chainId: 137 },
    { address: "0x495076C91684612AF7aD3E2018F14F578dC2c8F2", chainId: 137 },
    { address: "0x661fBb2d403D472DA7214D7efb3DA3bB3e6854fb", chainId: 137 },
    { address: "0x35C10235F444f00d2329162Fda534149D51A3b82", chainId: 137 },
  ];

  // Add nominees
  await vw.addNomineeEVM(contracts[0].address, contracts[0].chainId);
  await vw.addNomineeEVM(contracts[1].address, contracts[1].chainId);
  await vw.addNomineeEVM(contracts[2].address, contracts[2].chainId);
  await vw.addNomineeEVM(contracts[3].address, contracts[3].chainId);
  await vw.addNomineeEVM(contracts[4].address, contracts[4].chainId);
  await vw.addNomineeEVM(contracts[5].address, contracts[5].chainId);
  await vw.addNomineeEVM(contracts[6].address, contracts[6].chainId);
  await vw.addNomineeEVM(contracts[7].address, contracts[7].chainId);
  await vw.addNomineeEVM(contracts[8].address, contracts[8].chainId);
  await vw.addNomineeEVM(contracts[9].address, contracts[9].chainId);

  await olas.mint(signers[0].address, OLASBalance);
  // Lock OLASBalance into veOLAS for 1st signer
  await olas.approve(ve.address, OLASBalance);
  await ve.createLock(OLASBalance, oneYear);

  // 1st signer voting
  await vw.voteForNomineeWeights(
    convertAddressToBytes32(contracts[0].address),
    contracts[0].chainId,
    2000
  );
  await vw.voteForNomineeWeights(
    convertAddressToBytes32(contracts[1].address),
    contracts[1].chainId,
    2000
  );
  await vw.voteForNomineeWeights(
    convertAddressToBytes32(contracts[2].address),
    contracts[2].chainId,
    1000
  );
  await vw.voteForNomineeWeights(
    convertAddressToBytes32(contracts[3].address),
    contracts[3].chainId,
    500
  );
  await vw.voteForNomineeWeights(
    convertAddressToBytes32(contracts[4].address),
    contracts[4].chainId,
    4000
  );

  let block = await ethers.provider.getBlock("latest");
  let nextTime = Math.floor((block.timestamp + oneWeek) / oneWeek) * oneWeek;
  console.log(
    "votes",
    await vw.nomineeRelativeWeight(
      convertAddressToBytes32(contracts[0].address),
      contracts[0].chainId,
      block.timestamp
    )
  );
  console.log(
    "votes next week",
    await vw.nomineeRelativeWeight(
      convertAddressToBytes32(contracts[0].address),
      contracts[0].chainId,
      nextTime
    )
  );
  console.log("block", block.timestamp, "next", nextTime);

  await olas.mint(signers[1].address, OLASBalance);
  // Lock one OLAS into veOLAS for 2d signer
  await olas.connect(signers[1]).approve(ve.address, OLASBalance);
  await ve.connect(signers[1]).createLock(OLASBalance, oneYear);

  // 2d signer voting
  await vw
    .connect(signers[1])
    .voteForNomineeWeights(
      convertAddressToBytes32(contracts[4].address),
      contracts[4].chainId,
      5000
    );
  await vw
    .connect(signers[1])
    .voteForNomineeWeights(
      convertAddressToBytes32(contracts[5].address),
      contracts[5].chainId,
      1000
    );
  await vw
    .connect(signers[1])
    .voteForNomineeWeights(
      convertAddressToBytes32(contracts[7].address),
      contracts[7].chainId,
      1000
    );
  await vw
    .connect(signers[1])
    .voteForNomineeWeights(
      convertAddressToBytes32(contracts[8].address),
      contracts[8].chainId,
      1000
    );
  await vw
    .connect(signers[1])
    .voteForNomineeWeights(
      convertAddressToBytes32(contracts[9].address),
      contracts[9].chainId,
      500
    );

  console.log("olas address", olas.address);
  console.log("veolas address", ve.address);
  console.log("vote weighting address", vw.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
