/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

pragma solidity ^0.8.20;

contract TestAutoPriceSource is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    uint256 public price;
    uint256 public updatedAt;
    uint256 public roundId;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    function getMarkPrice() external view returns (uint256) {
        // Change 1% every minute
        // -50% -> 50% -> -50%
        // 0 -> 100min -> 200min
        uint256 timeOffset = (block.timestamp / 60) % 200; // min
        if (timeOffset <= 100) {
            return price / 2 + (timeOffset * price) / 100;
        } else {
            return price + price / 2 - ((timeOffset - 100) * price) / 100;
        }
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        roundId++;
        updatedAt = block.timestamp;
        emit AnswerUpdated(SafeCast.toInt256(price), roundId, updatedAt);
    }
}
