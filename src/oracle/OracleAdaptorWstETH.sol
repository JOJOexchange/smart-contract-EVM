/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IChainlink.sol";
import "../libraries/Types.sol";

contract JOJOOracleAdaptorWstETH is Ownable {
    uint256 public immutable decimalsCorrection;
    uint256 public immutable heartbeatInterval;
    uint256 public immutable usdcHeartbeat;
    uint256 public immutable ETHHeartbeat;
    address public immutable chainlink;
    address public immutable usdcSource;
    address public immutable ETHSource;

    constructor(
        address _source,
        uint256 _decimalCorrection,
        uint256 _heartbeatInterval,
        address _usdcSource,
        uint256 _usdcHeartbeat,
        address _ETHSource,
        uint256 _ETHHeartbeat
    ) {
        chainlink = _source;
        decimalsCorrection = 10 ** _decimalCorrection;
        heartbeatInterval = _heartbeatInterval;
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
        ETHSource = _ETHSource;
        ETHHeartbeat = _ETHHeartbeat;
    }

    function getAssetPrice() external view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = IChainlink(chainlink).latestRoundData();
        (, int256 usdcPrice,, uint256 usdcUpdatedAt,) = IChainlink(usdcSource).latestRoundData();
        (, int256 ETHPrice,, uint256 ETHUpdatedAt,) = IChainlink(ETHSource).latestRoundData();

        require(block.timestamp - updatedAt <= heartbeatInterval, "ORACLE_HEARTBEAT_FAILED");
        require(block.timestamp - usdcUpdatedAt <= usdcHeartbeat, "USDC_ORACLE_HEARTBEAT_FAILED");
        require(block.timestamp - ETHUpdatedAt <= ETHHeartbeat, "ETH_ORACLE_HEARTBEAT_FAILED");
        uint256 tokenPrice = (((SafeCast.toUint256(price) * SafeCast.toUint256(ETHPrice)) / Types.ONE) * 1e8)
            / SafeCast.toUint256(usdcPrice);
        return (tokenPrice * Types.ONE) / decimalsCorrection;
    }
}
