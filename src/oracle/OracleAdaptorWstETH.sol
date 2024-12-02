/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IChainlink.sol";
import "../libraries/Types.sol";

contract JOJOOracleAdaptorWstETH is Ownable {
    uint256 public immutable heartbeatInterval;
    uint256 public immutable usdcHeartbeat;
    uint256 public immutable ETHHeartbeat;
    address public immutable wstetheth;
    address public immutable usdcusdSource;
    address public immutable ETHusdSource;

    constructor(
        address _wstetheth,
        uint256 _heartbeatInterval,
        address _usdcusdSource,
        uint256 _usdcHeartbeat,
        address _ETHusdSource,
        uint256 _ETHHeartbeat
    ) {
        wstetheth = _wstetheth;
        heartbeatInterval = _heartbeatInterval;
        usdcHeartbeat = _usdcHeartbeat;
        usdcusdSource = _usdcusdSource;
        ETHusdSource = _ETHusdSource;
        ETHHeartbeat = _ETHHeartbeat;
    }

    function getAssetPrice() external view returns (uint256) {
        (, int256 wstethethprice,, uint256 updatedAt,) = IChainlink(wstetheth).latestRoundData(); // 18 decimals
        (, int256 usdcusdPrice,, uint256 usdcUpdatedAt,) = IChainlink(usdcusdSource).latestRoundData(); // 8 decimals
        (, int256 ETHusdPrice,, uint256 ETHUpdatedAt,) = IChainlink(ETHusdSource).latestRoundData(); // 8 decimals

        require(block.timestamp - updatedAt <= heartbeatInterval, "ORACLE_HEARTBEAT_FAILED");
        require(block.timestamp - usdcUpdatedAt <= usdcHeartbeat, "USDC_ORACLE_HEARTBEAT_FAILED");
        require(block.timestamp - ETHUpdatedAt <= ETHHeartbeat, "ETH_ORACLE_HEARTBEAT_FAILED");
        return SafeCast.toUint256(wstethethprice * ETHusdPrice / usdcusdPrice)/1e12; // wstETH-USDC should be 6 decimals
    }
}
