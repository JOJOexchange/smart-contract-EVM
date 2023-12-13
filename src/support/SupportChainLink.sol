/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
pragma solidity ^^0.8.9;

contract SupportChainLink {
    uint256 public price;
    uint256 public updatedAt;
    uint80 public roundId;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    function setAssetPrice(uint256 newPrice) external {
        price = newPrice;
        roundId++;
        updatedAt = block.timestamp;
        emit AnswerUpdated(int256(price), roundId, updatedAt);
    }

    function getAssetPrice() external view returns (uint256) {
        return price;
    }
}
