/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IChainlink.sol";

contract OracleAdaptor is Ownable {
    uint256 public immutable decimalsCorrection;
    uint256 public immutable heartbeatInterval;
    uint256 public immutable usdcHeartbeat;
    address public immutable usdcSource;
    address public immutable chainlink;
    uint256 public roundId;
    uint256 public price;
    uint256 public priceThreshold;
    bool public isSelfOracle;

    // Align with chainlink
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    event UpdateThreshold(uint256 oldThreshold, uint256 newThreshold);

    constructor(
        address _chainlink,
        uint256 _decimalsCorrection,
        uint256 _heartbeatInterval,
        uint256 _usdcHeartbeat,
        address _usdcSource,
        uint256 _priceThreshold
    ) {
        chainlink = _chainlink;
        decimalsCorrection = 10 ** _decimalsCorrection;
        heartbeatInterval = _heartbeatInterval;
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
        priceThreshold = _priceThreshold;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit AnswerUpdated(SafeCast.toInt256(price), roundId, block.timestamp);
        roundId += 1;
    }

    function turnOnJOJOOracle() external onlyOwner {
        isSelfOracle = true;
    }

    function turnOffJOJOOracle() external onlyOwner {
        isSelfOracle = false;
    }

    function updateThreshold(uint256 newPriceThreshold) external onlyOwner {
        priceThreshold = newPriceThreshold;
        emit UpdateThreshold(priceThreshold, newPriceThreshold);
    }

    function getChainLinkPrice() public view returns (uint256) {
        int256 rawPrice;
        uint256 updatedAt;
        (, rawPrice,, updatedAt,) = IChainlink(chainlink).latestRoundData();
        (, int256 usdcPrice,, uint256 usdcUpdatedAt,) = IChainlink(usdcSource).latestRoundData();
        require(block.timestamp - updatedAt <= heartbeatInterval, "ORACLE_HEARTBEAT_FAILED");
        require(block.timestamp - usdcUpdatedAt <= usdcHeartbeat, "USDC_ORACLE_HEARTBEAT_FAILED");
        uint256 tokenPrice = (SafeCast.toUint256(rawPrice) * 1e8) / SafeCast.toUint256(usdcPrice);
        return (tokenPrice * 1e18) / decimalsCorrection;
    }

    function getPrice() internal view returns (uint256) {
        uint256 chainLinkPrice = getChainLinkPrice();
        if (isSelfOracle) {
            uint256 JOJOPrice = price;
            uint256 diff = JOJOPrice >= chainLinkPrice ? JOJOPrice - chainLinkPrice : chainLinkPrice - JOJOPrice;
            require((diff * 1e18) / chainLinkPrice <= priceThreshold, "deviation is too big");
            return price;
        } else {
            return chainLinkPrice;
        }
    }

    function getMarkPrice() external view returns (uint256) {
        return getPrice();
    }

    function getAssetPrice() external view returns (uint256) {
        return getPrice();
    }
}
