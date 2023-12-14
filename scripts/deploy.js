const hre = require("hardhat");

async function main() {
  const Dex = await hre.ethers.getContractFactory("dex");
  const dex = await Dex.deploy();

  await dex.waitForDeployment();

  console.log("Dex contract: ", await dex.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
