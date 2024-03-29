/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IPyth.sol";
import "../interfaces/internal/IChainlink.sol";

contract OracleAdaptor is Ownable {
    uint256 public immutable decimalsCorrection;
    uint256 public immutable heartbeatInterval;
    uint256 public immutable usdcHeartbeat;
    address public immutable usdcSource;
    address public immutable chainlink;
    bytes32 public immutable priceId;
    uint256 public price;
    uint256 public priceThreshold;
    IPyth public pyth;

    event UpdateThreshold(uint256 oldThreshold, uint256 newThreshold);

    constructor(
        address _chainlink,
        address _pythContract,
        uint256 _decimalsCorrection,
        uint256 _heartbeatInterval,
        uint256 _usdcHeartbeat,
        address _usdcSource,
        uint256 _priceThreshold,
        bytes32 _priceId
    ) {
        chainlink = _chainlink;
        pyth = IPyth(_pythContract);
        decimalsCorrection = 10 ** _decimalsCorrection;
        heartbeatInterval = _heartbeatInterval;
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
        priceThreshold = _priceThreshold;
        priceId = _priceId;
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
        return tokenPrice;
    }

    function getPrice() internal view returns (uint256) {
        uint256 chainLinkPrice = getChainLinkPrice();
        try pyth.getPrice(priceId) returns (PythStructs.Price memory pythPriceStruct) {
            uint256 pythPrice = SafeCast.toUint256(pythPriceStruct.price);
            uint256 diff = pythPrice >= chainLinkPrice ? pythPrice - chainLinkPrice : chainLinkPrice - pythPrice;
            if ((diff * 1e18) / chainLinkPrice <= priceThreshold) {
                return chainLinkPrice;
            } else {
                return pythPrice;
            }
        } catch {
            return chainLinkPrice;
        }
    }

    function getMarkPrice() external view returns (uint256) {
        return (getPrice() * 1e18) / decimalsCorrection;
    }

    function getAssetPrice() external view returns (uint256) {
        return (getPrice() * 1e18) / decimalsCorrection;
    }
}
