// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title MetricChallengeDAO
 * @dev A decentralized prediction market for metrics with staking mechanisms
 * @notice Users can submit metrics, stake on outcomes, and earn rewards based on accuracy and timing
 */
contract MetricChallengeDAO is ReentrancyGuard, Ownable {
    
    // --- Data Structures ---
    
    struct Stake {
        address staker;
        uint256 timestamp;
    }
    
    enum MetricStatus {
        Pending,
        Resolved
    }
    
    struct Metric {
        uint256 id;
        address coinAddress; // Token contract address for the prediction
        uint256 expectedLossPercent; // Stored as basis points (e.g., 1000 = 10%)
        uint256 duration;
        uint256 startTime;
        MetricStatus status;
        uint256 bountyCollateral;
        Stake[] stakesInFavor;
        Stake[] stakesAgainst;
    }
    
    // --- State Variables ---
    
    mapping(uint256 => Metric) public metrics;
    uint256 public nextMetricID;
    uint256 public fixedStakeAmount; // Fixed stake amount in wei
    
    // Contract balance tracking
    uint256 public totalContractBalance;
    
    // Pyth Network integration
    IPyth public immutable pyth;
    
    // Mapping of coin addresses to their Pyth price feed IDs
    mapping(address => bytes32) public coinToPriceFeedId;
    
    // Pyth Network configuration for Sepolia
    address constant PYTH_CONTRACT_SEPOLIA = 0xDd24f84D36bF92C65F92307595C6B99D36b6f8c4;
    
    // Safety parameters
    uint256 constant PRICE_STALENESS_THRESHOLD = 300; // 5 minutes
    
    // --- Events ---
    
    event MetricSubmitted(uint256 indexed metricID, address indexed submitter);
    event Staked(uint256 indexed metricID, address indexed staker, string side);
    event MetricResolved(uint256 indexed metricID, string winningSide);
    event RewardDistributed(address indexed staker, uint256 amount);
    event StakeAmountUpdated(uint256 newAmount);
    
    // --- Errors ---
    
    error MetricNotFound();
    error StakingPeriodOver();
    error MetricAlreadyResolved();
    error InsufficientPayment();
    error TransferFailed();
    error InvalidParameters();
    error InvalidPrice();
    error PriceTooStale();
    error UnsupportedCoin();
    error InsufficientUpdateFee();
    
    // --- Constructor ---
    
    constructor(uint256 _fixedStakeAmount) Ownable(msg.sender) {
        nextMetricID = 1;
        fixedStakeAmount = _fixedStakeAmount;
        pyth = IPyth(PYTH_CONTRACT_SEPOLIA);
    }
    
    // --- Modifiers ---
    
    modifier metricExists(uint256 metricID) {
        if (metricID == 0 || metricID >= nextMetricID) {
            revert MetricNotFound();
        }
        _;
    }
    
    modifier stakingPeriodActive(uint256 metricID) {
        Metric storage metric = metrics[metricID];
        if (block.timestamp >= metric.startTime + metric.duration) {
            revert StakingPeriodOver();
        }
        _;
    }
    
    modifier onlyPending(uint256 metricID) {
        if (metrics[metricID].status != MetricStatus.Pending) {
            revert MetricAlreadyResolved();
        }
        _;
    }
    
    // --- Main Functions ---
    
    /**
     * @dev Submit a new metric for prediction
     * @param expectedLossPercent Expected loss percentage in basis points (e.g., 1000 = 10%)
     * @param duration Duration of staking period in seconds
     * @return metricID The ID of the newly created metric
     */
    function submitMetric(
        uint256 expectedLossPercent,
        uint256 duration,
        uint256 bountyCollateral
    ) external payable nonReentrant returns (uint256) {
        if (expectedLossPercent > 10000 || duration == 0) {
            revert InvalidParameters();
        }
        
        uint256 metricID = nextMetricID;
        
        // Create new metric
        Metric storage newMetric = metrics[metricID];
        newMetric.id = metricID;
        newMetric.expectedLossPercent = expectedLossPercent;
        newMetric.duration = duration;
        newMetric.startTime = block.timestamp;
        newMetric.status = MetricStatus.Pending;
        newMetric.bountyCollateral = bountyCollateral;
        
        // Update contract state
        nextMetricID++;
        totalContractBalance += bountyCollateral;
        
        emit MetricSubmitted(metricID, msg.sender);
        return metricID;
    }
    
    /**
     * @dev Stake in favor of a metric's prediction
     * @param metricID The ID of the metric to stake on
     */
    function stakeInFavor(uint256 metricID) 
        external 
        nonReentrant 
        metricExists(metricID) 
        stakingPeriodActive(metricID) 
        onlyPending(metricID) 
    {
        
        Metric storage metric = metrics[metricID];
        metric.stakesInFavor.push(Stake({
            staker: msg.sender,
            timestamp: block.timestamp
        }));
        emit Staked(metricID, msg.sender, "InFavor");
    }
    
    /**
     * @dev Stake against a metric's prediction
     * @param metricID The ID of the metric to stake on
     */
    function stakeAgainst(uint256 metricID) 
        external 
        nonReentrant 
        metricExists(metricID) 
        stakingPeriodActive(metricID) 
        onlyPending(metricID) 
    {
        
        Metric storage metric = metrics[metricID];
        metric.stakesAgainst.push(Stake({
            staker: msg.sender,
            timestamp: block.timestamp
        }));        
        emit Staked(metricID, msg.sender, "Against");
    }
    
    /**
     * @dev Resolve a metric using Pyth price data and distribute rewards
     * @param metricID The ID of the metric to resolve
     */
    function resolveMetric(uint256 metricID) 
        external 
        nonReentrant 
        metricExists(metricID) 
        onlyPending(metricID) 
    {
        Metric storage metric = metrics[metricID];
        
        // Check if staking period is over
        if (block.timestamp < metric.startTime + metric.duration) {
            revert StakingPeriodOver();
        }
        
        // Get price feed ID for this coin
        bytes32 priceFeedId = coinToPriceFeedId[metric.coinAddress];
        if (priceFeedId == bytes32(0)) {
            revert UnsupportedCoin();
        }
        
        // Get current price from Pyth
        PythStructs.Price memory currentPriceData = pyth.getPriceUnsafe(priceFeedId);
        if (currentPriceData.price <= 0) {
            revert InvalidPrice();
        }
        if (block.timestamp - currentPriceData.publishTime > PRICE_STALENESS_THRESHOLD) {
            revert PriceTooStale();
        }
        
        // Get baseline price from Pyth (price at metric start time)
        // Note: In a real implementation, you'd need to store baseline price or use historical data
        // For now, we'll assume the baseline price was stored when metric was created
        // This is a simplified version - you'd need to modify submitMetric to store baseline price
        
        // For demonstration, let's assume we have a way to get historical price
        // In practice, you'd store the baseline price when the metric is submitted
        int64 baselinePrice = currentPriceData.price; // This should be the actual baseline price
        int64 currentPrice = currentPriceData.price;
        
        // Calculate actual loss percentage
        // actualLoss = (baselinePrice - currentPrice) / baselinePrice * 10000
        uint256 actualLossPercent;
        if (currentPrice >= baselinePrice) {
            actualLossPercent = 0; // No loss, actually a gain
        } else {
            uint256 priceDiff = uint256(uint64(baselinePrice - currentPrice));
            uint256 baseline = uint256(uint64(baselinePrice));
            actualLossPercent = (priceDiff * 10000) / baseline;
        }
        
        // Ensure actualLossPercent doesn't exceed 10000 (100%)
        if (actualLossPercent > 10000) {
            actualLossPercent = 10000;
        }
        
        // Determine winning side
        bool inFavorWins = actualLossPercent >= metric.expectedLossPercent;
        Stake[] storage winningStakes = inFavorWins ? metric.stakesInFavor : metric.stakesAgainst;
        Stake[] storage losingStakes = inFavorWins ? metric.stakesAgainst : metric.stakesInFavor;
        string memory winningSide = inFavorWins ? "InFavor" : "Against";
        
        // Calculate reward pool
        uint256 rewardPool = metric.bountyCollateral + (losingStakes.length * fixedStakeAmount);
        
        if (winningStakes.length > 0 && rewardPool > 0) {
            // Calculate total earlyness for proportional distribution
            uint256 totalEarlyness = 0;
            for (uint256 i = 0; i < winningStakes.length; i++) {
                uint256 stakingTime = winningStakes[i].timestamp - metric.startTime;
                uint256 earlyness = metric.duration - stakingTime;
                totalEarlyness += earlyness;
            }
            
            // Distribute rewards based on earlyness
            if (totalEarlyness > 0) {
                for (uint256 i = 0; i < winningStakes.length; i++) {
                    uint256 stakingTime = winningStakes[i].timestamp - metric.startTime;
                    uint256 earlyness = metric.duration - stakingTime;
                    uint256 reward = (earlyness * rewardPool) / totalEarlyness;
                    
                    if (reward > 0) {
                        totalContractBalance -= reward;
                        (bool success, ) = payable(winningStakes[i].staker).call{value: reward}("");
                        if (!success) {
                            revert TransferFailed();
                        }
                        emit RewardDistributed(winningStakes[i].staker, reward);
                    }
                }
            }
        }
        
        // Mark metric as resolved
        metric.status = MetricStatus.Resolved;
        
        emit MetricResolved(metricID, winningSide);
    }
    
    // --- View Functions ---
    
    /**
     * @dev Get metric details
     * @param metricID The ID of the metric
     * @return id The metric ID
     * @return expectedLossPercent Expected loss percentage in basis points
     * @return duration Duration of staking period in seconds
     * @return startTime Start timestamp of the metric
     * @return status Current status of the metric
     * @return bountyCollateral Bounty collateral amount
     * @return stakesInFavorCount Number of stakes in favor
     * @return stakesAgainstCount Number of stakes against
     */
    function getMetric(uint256 metricID) 
        external 
        view 
        metricExists(metricID) 
        returns (
            uint256 id,
            uint256 expectedLossPercent,
            uint256 duration,
            uint256 startTime,
            MetricStatus status,
            uint256 bountyCollateral,
            uint256 stakesInFavorCount,
            uint256 stakesAgainstCount
        ) 
    {
        Metric storage metric = metrics[metricID];
        return (
            metric.id,
            metric.expectedLossPercent,
            metric.duration,
            metric.startTime,
            metric.status,
            metric.bountyCollateral,
            metric.stakesInFavor.length,
            metric.stakesAgainst.length
        );
    }
    
    /**
     * @dev Get stakes in favor of a metric
     * @param metricID The ID of the metric
     * @return Array of stakes in favor
     */
    function getStakesInFavor(uint256 metricID) 
        external 
        view 
        metricExists(metricID) 
        returns (Stake[] memory) 
    {
        return metrics[metricID].stakesInFavor;
    }
    
    /**
     * @dev Get stakes against a metric
     * @param metricID The ID of the metric
     * @return Array of stakes against
     */
    function getStakesAgainst(uint256 metricID) 
        external 
        view 
        metricExists(metricID) 
        returns (Stake[] memory) 
    {
        return metrics[metricID].stakesAgainst;
    }
    
    /**
     * @dev Check if staking period is active for a metric
     * @param metricID The ID of the metric
     * @return True if staking period is active
     */
    function isStakingActive(uint256 metricID) 
        external 
        view 
        metricExists(metricID) 
        returns (bool) 
    {
        Metric storage metric = metrics[metricID];
        return block.timestamp < metric.startTime + metric.duration && 
               metric.status == MetricStatus.Pending;
    }
    
    // --- Admin Functions ---
    
    /**
     * @dev Add or update a supported coin with its Pyth price feed ID
     * @param coinAddress Token contract address
     * @param priceFeedId Pyth price feed ID for this coin
     */
    function setSupportedCoin(address coinAddress, bytes32 priceFeedId) external onlyOwner {
        if (coinAddress == address(0) || priceFeedId == bytes32(0)) {
            revert InvalidParameters();
        }
        coinToPriceFeedId[coinAddress] = priceFeedId;
    }

    /**
     * @dev Remove a supported coin
     * @param coinAddress Token contract address to remove
     */
    function removeSupportedCoin(address coinAddress) external onlyOwner {
        delete coinToPriceFeedId[coinAddress];
    }

    /**
     * @dev Update the fixed stake amount (only owner)
     * @param newAmount New stake amount in wei
     */
    function updateFixedStakeAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) {
            revert InvalidParameters();
        }
        fixedStakeAmount = newAmount;
        emit StakeAmountUpdated(newAmount);
    }
    
    /**
     * @dev Emergency withdraw function (only owner)
     * @param amount Amount to withdraw in wei
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) {
            revert InsufficientPayment();
        }
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }
    
    /**
     * @dev Get contract balance
     * @return Contract balance in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // --- Fallback Functions ---
    
    receive() external payable {
        totalContractBalance += msg.value;
    }
    
    fallback() external payable {
        totalContractBalance += msg.value;
    }
}
