const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Deploying Updated MetricChallengeDAO to Sepolia...");
    
    // Get the deployer account
    const [deployer] = await ethers.getSigners();
    console.log("📝 Deploying with account:", deployer.address);
    
    // Check deployer balance
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");
    
    if (balance < ethers.parseEther("0.01")) {
        console.warn("⚠️  Warning: Low balance. You may need more ETH for deployment and testing.");
    }
    
    // Deploy MetricChallengeDAO
    console.log("\n📦 Deploying MetricChallengeDAO...");
    const MetricChallengeDAO = await ethers.getContractFactory("MetricChallengeDAO");
    
    // Fixed stake amount: 0.01 ETH
    const fixedStakeAmount = ethers.parseEther("0.01");
    
    const daoContract = await MetricChallengeDAO.deploy(fixedStakeAmount);
    await daoContract.waitForDeployment();
    
    const daoContractAddress = await daoContract.getAddress();
    console.log("✅ MetricChallengeDAO deployed to:", daoContractAddress);
    
    // Set up supported coins with their Pyth price feed IDs
    console.log("\n🔧 Setting up supported coins...");
    
    // ETH price feed ID (this is a placeholder address for ETH)
    const ETH_ADDRESS = "0x0000000000000000000000000000000000000000"; // Use zero address for ETH
    const ETH_PRICE_FEED_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";
    
    try {
        const tx = await daoContract.setSupportedCoin(ETH_ADDRESS, ETH_PRICE_FEED_ID);
        await tx.wait();
        console.log("✅ ETH price feed configured");
    } catch (error) {
        console.log("⚠️  Could not configure ETH price feed:", error.message);
    }
    
    // Verify contract setup
    console.log("\n🔍 Verifying contract setup...");
    try {
        const contractBalance = await daoContract.getContractBalance();
        const nextMetricID = await daoContract.nextMetricID();
        const stakeAmount = await daoContract.fixedStakeAmount();
        
        console.log("📊 Contract Info:");
        console.log("   - Contract Balance:", ethers.formatEther(contractBalance), "ETH");
        console.log("   - Next Metric ID:", nextMetricID.toString());
        console.log("   - Fixed Stake Amount:", ethers.formatEther(stakeAmount), "ETH");
        console.log("   - Pyth Contract:", "0xDd24f84D36bF92C65F92307595C6B99D36b6f8c4");
        
        // Check if ETH is supported
        const ethPriceFeedId = await daoContract.coinToPriceFeedId(ETH_ADDRESS);
        console.log("   - ETH Price Feed ID:", ethPriceFeedId);
        
    } catch (error) {
        console.log("⚠️  Could not verify contract info:", error.message);
    }
    
    // Display usage instructions
    console.log("\n📋 Enhanced Contract Features:");
    console.log("1. Dynamic Coin Support:");
    console.log("   - Metrics can be created for any supported cryptocurrency");
    console.log("   - Admin can add/remove supported coins with setSupportedCoin()");
    console.log("\n2. Automated Resolution:");
    console.log("   - resolveMetric() now only requires metricID parameter");
    console.log("   - Contract automatically fetches live price data from Pyth");
    console.log("   - Calculates actual loss percentage automatically");
    console.log("\n3. Pyth Integration:");
    console.log("   - Real-time price feeds from Pyth Network");
    console.log("   - Price staleness validation (5-minute threshold)");
    console.log("   - Support for multiple cryptocurrencies");
    
    // Save deployment info
    const deploymentInfo = {
        network: "sepolia",
        metricChallengeDAO: {
            address: daoContractAddress,
            deployer: deployer.address,
            deploymentTime: new Date().toISOString(),
            fixedStakeAmount: ethers.formatEther(fixedStakeAmount),
            pythContract: "0xDd24f84D36bF92C65F92307595C6B99D36b6f8c4",
            supportedCoins: {
                ETH: {
                    address: ETH_ADDRESS,
                    priceFeedId: ETH_PRICE_FEED_ID
                }
            }
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
    
    existingDeployment.metricChallengeDAO = deploymentInfo.metricChallengeDAO;
    fs.writeFileSync('deployment.json', JSON.stringify(existingDeployment, null, 2));
    
    console.log("\n💾 Deployment info saved to deployment.json");
    console.log("\n🎯 Next Steps:");
    console.log("1. Add more supported coins using setSupportedCoin()");
    console.log("2. Test metric submission with coinAddress parameter");
    console.log("3. Test automated resolution with resolveMetric(metricID)");
    console.log("4. Update frontend to work with new contract interface");
    
    return {
        metricChallengeDAO: daoContractAddress,
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
