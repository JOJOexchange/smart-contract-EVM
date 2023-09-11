/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/IChainlink.sol";


contract OracleAdaptor is Ownable {
    address public immutable chainlink;
    uint256 public immutable decimalsCorrection;
    uint256 public immutable heartbeatInterval;
    uint256 public immutable USDCHeartbeat;
    address public immutable USDCSource;

    uint256 public roundId;
    bool public isSelfOracle;
    uint256 public price;
    uint256 public priceThreshold;

    // Align with chainlink
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    event UpdateThreshold(uint256 oldThreshold, uint256 newThreshold);

    constructor(
        address _chainlink,
        uint256 _decimalsCorrection,
        uint256 _heartbeatInterval,
        uint256 _USDCHeartbeat,
        address _USDCSource,
        uint256 _priceThreshold
    ) {
        chainlink = _chainlink;
        decimalsCorrection = 10**_decimalsCorrection;
        heartbeatInterval = _heartbeatInterval;
        USDCHeartbeat = _USDCHeartbeat;
        USDCSource = _USDCSource;
        priceThreshold = _priceThreshold;
    }

    // token/usdc
    function setMarkPrice(uint256 newPrice) external onlyOwner{
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



    function getChainLinkPrice() public view returns(uint256) {
        int256 rawPrice;
        uint256 updatedAt;
        (, rawPrice, , updatedAt, ) = IChainlink(chainlink).latestRoundData();
        (, int256 USDCPrice,, uint256 USDCUpdatedAt,) = IChainlink(USDCSource).latestRoundData();
        require(
            block.timestamp - updatedAt <= heartbeatInterval,
            "ORACLE_HEARTBEAT_FAILED"
        );
        require(block.timestamp - USDCUpdatedAt <= USDCHeartbeat, "USDC_ORACLE_HEARTBEAT_FAILED");
        uint256 tokenPrice = (SafeCast.toUint256(rawPrice) * 1e8) / SafeCast.toUint256(USDCPrice);
        return tokenPrice * 1e18 / decimalsCorrection;
    }

    function getMarkPrice() external view returns(uint256) {
        uint256 chainLinkPrice = getChainLinkPrice();
        //self-build
        if(isSelfOracle){
            uint256 JOJOPrice = price;
            uint256 diff = JOJOPrice >= chainLinkPrice ? JOJOPrice - chainLinkPrice : chainLinkPrice - JOJOPrice;
            //Comparing diff and chainlink feed prices, who be the threshold, compare with whom; use chainlink for threshold
            require(diff * 1e18 / chainLinkPrice <= priceThreshold, "deviation is too big");

            return price;
        } else {
            //return chainLinkPrice
            return chainLinkPrice;
        }
    }
}
