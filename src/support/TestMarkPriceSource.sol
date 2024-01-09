/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

pragma solidity ^0.8.20;

contract TestMarkPriceSource is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    uint256 public price;
    uint256 public updatedAt;
    uint256 public roundId;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    function getMarkPrice() external view returns (uint256) {
        return price;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        roundId++;
        updatedAt = block.timestamp;
        emit AnswerUpdated(SafeCast.toInt256(price), roundId, updatedAt);
    }
}
