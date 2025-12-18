const { ethers } = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const deploymentsDir = path.join(__dirname, '../deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir);
  }

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

  const deploymentLog = {
    contractAddress: await vaultis.getAddress(),
    constructorInputs: {
      xTokenAddress: xTokenAddress,
      yTokenAddress: yTokenAddress,
    },
    adminWalletAddress: deployer.address,
  };

  const logFilePath = path.join(deploymentsDir, 'deployment-log.json');
  fs.writeFileSync(logFilePath, JSON.stringify(deploymentLog, null, 2));
  console.log("Deployment details saved to:", logFilePath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
