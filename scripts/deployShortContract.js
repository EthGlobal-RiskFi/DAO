const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Deploying SimpleShortContract to Sepolia...");
    
    // Get the deployer account
    const [deployer] = await ethers.getSigners();
    console.log("📝 Deploying with account:", deployer.address);
    
    // Check deployer balance
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");
    
    if (balance < ethers.parseEther("0.01")) {
        console.warn("⚠️  Warning: Low balance. You may need more ETH for deployment and testing.");
    }
    
    // Deploy SimpleShortContract
    console.log("\n📦 Deploying SimpleShortContract...");
    const SimpleShortContract = await ethers.getContractFactory("SimpleShortContract");
    
    // Deploy the contract
    const shortContract = await SimpleShortContract.deploy();
    await shortContract.waitForDeployment();
    
    const shortContractAddress = await shortContract.getAddress();
    console.log("✅ SimpleShortContract deployed to:", shortContractAddress);
    
    // Verify contract info
    console.log("\n🔍 Verifying contract setup...");
    try {
        const contractInfo = await shortContract.getContractInfo();
        console.log("📊 Contract Info:");
        console.log("   - Contract Balance:", ethers.formatEther(contractInfo[0]), "ETH");
        console.log("   - Pyth Contract:", contractInfo[1]);
        console.log("   - ETH/USD Price Feed ID:", contractInfo[2]);
        
        // Try to get current price (may fail if no recent updates)
        try {
            const [price, timestamp] = await shortContract.getCurrentPrice();
            console.log("   - Current ETH Price:", (Number(price) / 1e8).toFixed(2), "USD");
            console.log("   - Price Timestamp:", new Date(Number(timestamp) * 1000).toISOString());
        } catch (error) {
            console.log("   - Price Status: ⚠️  No recent price data (normal for fresh deployment)");
        }
        
    } catch (error) {
        console.log("⚠️  Could not verify contract info:", error.message);
    }
    
    // Display usage instructions
    console.log("\n📋 Contract Usage Instructions:");
    console.log("1. To open a short position:");
    console.log("   - Call openShort() with Pyth price update data");
    console.log("   - Send ETH as collateral (minimum 0.001 ETH)");
    console.log("   - Price update data can be obtained from Pyth Hermes API");
    console.log("\n2. To close a short position:");
    console.log("   - Call closeShort() with current Pyth price update data");
    console.log("   - Send small amount of ETH to cover price update fees");
    console.log("\n3. To monitor position:");
    console.log("   - Call viewPnL() to see current profit/loss");
    console.log("   - Call getPosition() to see position details");
    
    // Save deployment info
    const deploymentInfo = {
        network: "sepolia",
        shortContract: {
            address: shortContractAddress,
            deployer: deployer.address,
            deploymentTime: new Date().toISOString(),
            pythContract: "0xDd24f84D36bF92C65F92307595C6B99D36b6f8c4",
            ethUsdPriceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
        }
    };
    
    // Update deployment.json
    const fs = require('fs');
    let existingDeployment = {};
    try {
        const deploymentData = fs.readFileSync('deployment.json', 'utf8');
        existingDeployment = JSON.parse(deploymentData);
    } catch (error) {
        console.log("📄 Creating new deployment.json file");
    }
    
    existingDeployment.shortContract = deploymentInfo.shortContract;
    fs.writeFileSync('deployment.json', JSON.stringify(existingDeployment, null, 2));
    
    console.log("\n💾 Deployment info saved to deployment.json");
    console.log("\n🎯 Next Steps:");
    console.log("1. Install new dependencies: npm install");
    console.log("2. Verify contract on Etherscan (optional)");
    console.log("3. Test shorting functionality with frontend");
    console.log("4. Get Pyth price update data from: https://hermes.pyth.network/");
    
    return {
        shortContract: shortContractAddress,
        deployer: deployer.address
    };
}

// Handle both direct execution and module export
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error("❌ Deployment failed:", error);
            process.exit(1);
        });
}

module.exports = main;
