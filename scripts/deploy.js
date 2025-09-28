const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Starting MetricChallengeDAO deployment...\n");

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("📝 Deploying contracts with account:", deployer.address);
  
  // Check deployer balance
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", ethers.formatEther(balance), "ETH\n");

  // Set deployment parameters
  const FIXED_STAKE_AMOUNT = ethers.parseEther("0.01"); // 0.01 ETH stake amount
  
  console.log("⚙️  Deployment Parameters:");
  console.log("   Fixed Stake Amount:", ethers.formatEther(FIXED_STAKE_AMOUNT), "ETH");
  console.log("   Network:", network.name);
  console.log("   Chain ID:", network.config.chainId, "\n");

  // Deploy the contract
  console.log("📦 Deploying MetricChallengeDAO contract...");
  const MetricChallengeDAO = await ethers.getContractFactory("MetricChallengeDAO");
  
  const metricDAO = await MetricChallengeDAO.deploy(FIXED_STAKE_AMOUNT);
  await metricDAO.waitForDeployment();
  
  const contractAddress = await metricDAO.getAddress();
  console.log("✅ MetricChallengeDAO deployed to:", contractAddress);

  // Verify deployment
  console.log("\n🔍 Verifying deployment...");
  const deployedStakeAmount = await metricDAO.fixedStakeAmount();
  const nextMetricID = await metricDAO.nextMetricID();
  const owner = await metricDAO.owner();
  
  console.log("   Fixed Stake Amount:", ethers.formatEther(deployedStakeAmount), "ETH");
  console.log("   Next Metric ID:", nextMetricID.toString());
  console.log("   Contract Owner:", owner);
  console.log("   Deployer Address:", deployer.address);
  console.log("   Owner Match:", owner === deployer.address ? "✅" : "❌");

  // Display contract information
  console.log("\n📋 Contract Information:");
  console.log("┌─────────────────────────────────────────────────────────────┐");
  console.log("│                    DEPLOYMENT SUMMARY                      │");
  console.log("├─────────────────────────────────────────────────────────────┤");
  console.log(`│ Contract Name: MetricChallengeDAO                           │`);
  console.log(`│ Network: ${network.name.padEnd(49)} │`);
  console.log(`│ Address: ${contractAddress.padEnd(47)} │`);
  console.log(`│ Stake Amount: ${ethers.formatEther(FIXED_STAKE_AMOUNT).padEnd(43)} ETH │`);
  console.log("└─────────────────────────────────────────────────────────────┘");

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.config.chainId,
    contractAddress: contractAddress,
    fixedStakeAmount: ethers.formatEther(FIXED_STAKE_AMOUNT),
    deployerAddress: deployer.address,
    deploymentTime: new Date().toISOString(),
    blockNumber: await ethers.provider.getBlockNumber(),
  };

  console.log("\n💾 Deployment info saved to deployment.json");
  
  // Write deployment info to file
  const fs = require("fs");
  fs.writeFileSync("deployment.json", JSON.stringify(deploymentInfo, null, 2));

  // Contract verification instructions
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\n🔐 To verify the contract on Etherscan, run:");
    console.log(`npx hardhat verify --network ${network.name} ${contractAddress} "${FIXED_STAKE_AMOUNT}"`);
  }

  // Usage examples
  console.log("\n📚 Usage Examples:");
  console.log("   Submit Metric: Send ETH as bounty collateral");
  console.log("   Stake In Favor: Send exactly", ethers.formatEther(FIXED_STAKE_AMOUNT), "ETH");
  console.log("   Stake Against: Send exactly", ethers.formatEther(FIXED_STAKE_AMOUNT), "ETH");
  console.log("   Resolve Metric: Only contract owner can resolve");

  console.log("\n🎉 Deployment completed successfully!");
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
