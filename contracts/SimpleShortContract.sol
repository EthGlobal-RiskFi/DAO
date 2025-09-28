// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleShortContract
 * @dev A simple ETH shorting contract using Pyth Network price feeds
 * @notice Users can open short positions on ETH and profit from price decreases
 */
contract SimpleShortContract is ReentrancyGuard, Ownable {
    IPyth public immutable pyth;
    
    struct ShortPosition {
        uint256 collateralAmount;    // ETH collateral provided
        int64 entryPrice;           // Price when short opened (8 decimals)
        uint256 timestamp;          // When position opened
        bool active;               // Position status
    }
    
    mapping(address => ShortPosition) public positions;
    
    // Pyth Network configuration for Sepolia
    address constant PYTH_CONTRACT_SEPOLIA = 0xDd24f84D36bF92C65F92307595C6B99D36b6f8c4;
    
    // ETH/USD price feed ID from Pyth Network
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    
    // Safety parameters
    uint256 constant PRICE_STALENESS_THRESHOLD = 300; // 5 minutes
    uint256 constant MAX_PROFIT_PERCENTAGE = 200; // 200% max profit
    uint256 constant MIN_COLLATERAL = 0.001 ether; // Minimum 0.001 ETH
    
    // Events
    event ShortOpened(address indexed user, uint256 collateral, int64 price, uint256 timestamp);
    event ShortClosed(address indexed user, int256 pnl, int64 exitPrice, uint256 timestamp);
    event EmergencyWithdraw(address indexed owner, uint256 amount);
    
    // Custom errors
    error InsufficientCollateral();
    error PositionAlreadyExists();
    error NoActivePosition();
    error InvalidPrice();
    error PriceTooStale();
    error TransferFailed();
    error InsufficientUpdateFee();
    
    constructor() Ownable(msg.sender) {
        pyth = IPyth(PYTH_CONTRACT_SEPOLIA);
    }
    
    /**
     * @dev Get current ETH price with validation
     * @return price Current ETH/USD price (8 decimals)
     * @return timestamp Price publish timestamp
     */
    function getCurrentPrice() public view returns (int64 price, uint64 timestamp) {
        PythStructs.Price memory priceData = pyth.getPriceUnsafe(ETH_USD_PRICE_ID);
        
        if (priceData.price <= 0) revert InvalidPrice();
        if (block.timestamp - priceData.publishTime > PRICE_STALENESS_THRESHOLD) {
            revert PriceTooStale();
        }
        
        return (priceData.price, uint64(priceData.publishTime));
    }
    
    /**
     * @dev Open a short position on ETH
     * @param priceUpdateData Pyth price update data
     */
    function openShort(bytes[] calldata priceUpdateData) external payable nonReentrant {
        if (msg.value < MIN_COLLATERAL) revert InsufficientCollateral();
        if (positions[msg.sender].active) revert PositionAlreadyExists();
        
        // Calculate update fee
        uint updateFee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value <= updateFee) revert InsufficientUpdateFee();
        
        // Update Pyth price feeds
        pyth.updatePriceFeeds{value: updateFee}(priceUpdateData);
        
        // Get current ETH price with validation
        (int64 currentPrice, ) = getCurrentPrice();
        
        // Calculate actual collateral after update fee
        uint256 actualCollateral = msg.value - updateFee;
        
        // Store position
        positions[msg.sender] = ShortPosition({
            collateralAmount: actualCollateral,
            entryPrice: currentPrice,
            timestamp: block.timestamp,
            active: true
        });
        
        emit ShortOpened(msg.sender, actualCollateral, currentPrice, block.timestamp);
    }
    
    /**
     * @dev Close short position and calculate P&L
     * @param priceUpdateData Pyth price update data
     */
    function closeShort(bytes[] calldata priceUpdateData) external payable nonReentrant {
        ShortPosition storage position = positions[msg.sender];
        if (!position.active) revert NoActivePosition();
        
        // Calculate update fee
        uint updateFee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value < updateFee) revert InsufficientUpdateFee();
        
        // Update Pyth price feeds
        pyth.updatePriceFeeds{value: updateFee}(priceUpdateData);
        
        // Get current ETH price with validation
        (int64 currentPrice, ) = getCurrentPrice();
        
        // Calculate P&L: profit if price went down, loss if price went up
        int256 priceDiff = position.entryPrice - currentPrice;
        int256 pnlPercentage = (priceDiff * 10000) / position.entryPrice; // Basis points
        int256 pnl = (int256(position.collateralAmount) * pnlPercentage) / 10000;
        
        // Calculate final payout with profit cap
        uint256 finalPayout = 0;
        if (pnl > 0) {
            // Profit: cap at MAX_PROFIT_PERCENTAGE
            uint256 profit = uint256(pnl);
            uint256 maxProfit = (position.collateralAmount * MAX_PROFIT_PERCENTAGE) / 100;
            if (profit > maxProfit) {
                profit = maxProfit;
            }
            finalPayout = position.collateralAmount + profit;
        } else {
            // Loss: subtract from collateral
            uint256 loss = uint256(-pnl);
            if (loss >= position.collateralAmount) {
                finalPayout = 0; // Total loss
            } else {
                finalPayout = position.collateralAmount - loss;
            }
        }
        
        // Mark position as closed
        position.active = false;
        
        // Send payout (subtract update fee if any remaining)
        if (finalPayout > 0) {
            (bool success, ) = payable(msg.sender).call{value: finalPayout}("");
            if (!success) revert TransferFailed();
        }
        
        // Refund excess ETH sent for update fee
        if (msg.value > updateFee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - updateFee}("");
            if (!success) revert TransferFailed();
        }
        
        emit ShortClosed(msg.sender, pnl, currentPrice, block.timestamp);
    }
    
    /**
     * @dev View current P&L without closing position
     * @param user Address of the user
     * @return pnl Current profit/loss in wei
     * @return currentPrice Current ETH price
     * @return pnlPercentage P&L as percentage (basis points)
     */
    function viewPnL(address user) external view returns (int256 pnl, int64 currentPrice, int256 pnlPercentage) {
        ShortPosition storage position = positions[user];
        if (!position.active) revert NoActivePosition();
        
        // Get current price (may revert if stale)
        (currentPrice, ) = getCurrentPrice();
        
        // Calculate P&L
        int256 priceDiff = position.entryPrice - currentPrice;
        pnlPercentage = (priceDiff * 10000) / position.entryPrice; // Basis points
        pnl = (int256(position.collateralAmount) * pnlPercentage) / 10000;
        
        return (pnl, currentPrice, pnlPercentage);
    }
    
    /**
     * @dev Get position details for a user
     * @param user Address of the user
     * @return position The user's position details
     */
    function getPosition(address user) external view returns (ShortPosition memory position) {
        return positions[user];
    }
    
    /**
     * @dev Check if user has an active position
     * @param user Address of the user
     * @return hasPosition True if user has active position
     */
    function hasActivePosition(address user) external view returns (bool hasPosition) {
        return positions[user].active;
    }
    
    /**
     * @dev Get the required update fee for price updates
     * @param priceUpdateData Pyth price update data
     * @return fee Required fee in wei
     */
    function getUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint fee) {
        return pyth.getUpdateFee(priceUpdateData);
    }
    
    /**
     * @dev Get contract statistics
     * @return totalBalance Total ETH balance in contract
     * @return pythContract Address of Pyth contract
     * @return priceId ETH/USD price feed ID
     */
    function getContractInfo() external view returns (
        uint256 totalBalance,
        address pythContract,
        bytes32 priceId
    ) {
        return (
            address(this).balance,
            address(pyth),
            ETH_USD_PRICE_ID
        );
    }
    
    /**
     * @dev Emergency withdraw function (owner only)
     * @param amount Amount to withdraw (0 for all)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        uint256 withdrawAmount = amount == 0 ? address(this).balance : amount;
        require(withdrawAmount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = payable(owner()).call{value: withdrawAmount}("");
        if (!success) revert TransferFailed();
        
        emit EmergencyWithdraw(owner(), withdrawAmount);
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        // Allow contract to receive ETH for price updates and collateral
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        revert("Function not found");
    }
}
