/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
    uint256 public immutable USDCHeartbeat;
    address public immutable USDCSource;

    constructor(
        address _chainlink,
        uint256 _decimalsCorrection,
        uint256 _heartbeatInterval,
        uint256 _USDCHeartbeat,
        address _USDCSource
    ) {
        chainlink = _chainlink;
        decimalsCorrection = 10**_decimalsCorrection;
        heartbeatInterval = _heartbeatInterval;
        USDCHeartbeat = _USDCHeartbeat;
        USDCSource = _USDCSource;
    }

    function getMarkPrice() external view returns (uint256 price) {
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
}
