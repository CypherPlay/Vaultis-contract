const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Get constructor parameters from command line arguments
  const xTokenAddress = process.env.X_TOKEN_ADDRESS;
  const yTokenAddress = process.env.Y_TOKEN_ADDRESS;

  // Validate parameters
  if (!xTokenAddress || !yTokenAddress) {
    console.error("Error: X_TOKEN_ADDRESS and Y_TOKEN_ADDRESS must be provided as environment variables.");
    process.exit(1);
  }

  console.log("X Token Address:", xTokenAddress);
  console.log("Y Token Address:", yTokenAddress);

  // Deploy Vaultis contract
  const Vaultis = await ethers.getContractFactory("Vaultis");
  const vaultis = await Vaultis.deploy(xTokenAddress, yTokenAddress);

  await vaultis.waitForDeployment();

  console.log("Vaultis deployed to:", await vaultis.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
