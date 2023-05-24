/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../utils/Errors.sol";

interface IChainlink {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestAnswer() external view returns (int256 answer);
}

contract ChainlinkExpandAdaptor {
    address public immutable chainlink;
    uint256 public immutable decimalsCorrection;
    uint256 public immutable heartbeatInterval;
    address public immutable USDCSource;

    constructor(
        address _chainlink,
        uint256 _decimalsCorrection,
        uint256 _heartbeatInterval,
        address _USDCSource
    ) {
        chainlink = _chainlink;
        decimalsCorrection = 10**_decimalsCorrection;
        heartbeatInterval = _heartbeatInterval;
        USDCSource = _USDCSource;
    }

    function getMarkPrice() external view returns (uint256 price) {
        (uint80 roundID, int256 rawPrice, , uint256 updatedAt, uint80 answeredInRound) = IChainlink(chainlink).latestRoundData();
        (uint80 USDCRoundID, int256 USDCPrice, , uint256 USDCUpdatedAt, uint80 USDCAnsweredInRound) = IChainlink(USDCSource).latestRoundData();
        require(rawPrice> 0, Errors.CHAINLINK_PRICE_LESS_THAN_0);
        require(answeredInRound >= roundID, Errors.STALE_PRICE);
        require(USDCPrice> 0, Errors.USDC_CHAINLINK_PRICE_LESS_THAN_0);
        require(USDCAnsweredInRound >= USDCRoundID, Errors.USDC_STALE_PRICE);
        require(
            block.timestamp - updatedAt <= heartbeatInterval,
            "ORACLE_HEARTBEAT_FAILED"
        );
        require(block.timestamp - USDCUpdatedAt <= heartbeatInterval, "USDC_ORACLE_HEARTBEAT_FAILED");
        uint256 tokenPrice = (SafeCast.toUint256(rawPrice) * 1e8) / SafeCast.toUint256(USDCPrice);
        return tokenPrice * 1e18 / decimalsCorrection;
    }
}
