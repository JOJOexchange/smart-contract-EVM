/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IChainlink.sol";
import "../libraries/Types.sol";
import "./OracleAdaptor.sol";

contract OracleAdaptorCbeth is Ownable {
    uint256 public immutable cbEthRateHeartbeat;
    address public immutable cbEthRateSource;
    address public ethOracle;

    constructor(
        uint256 _cbEthRateHeartbeat,
        address _cbEthRateSource,
        address _ethOracle
    ) {
        cbEthRateSource = _cbEthRateSource;
        cbEthRateHeartbeat = _cbEthRateHeartbeat;
        ethOracle = _ethOracle;
    }

    function getAssetPrice() external view returns (uint256) {
        (, int256 cbEthRate,, uint256 cbEthUpdatedAt,) = IChainlink(cbEthRateSource).latestRoundData();
        uint256 ethPrice = OracleAdaptor(ethOracle).getAssetPrice();
        require(block.timestamp - cbEthUpdatedAt <= cbEthRateHeartbeat, "ETH_ORACLE_HEARTBEAT_FAILED");
        uint256 tokenPrice = (ethPrice * SafeCast.toUint256(cbEthRate)) / Types.ONE;
        return tokenPrice;
    }
}
