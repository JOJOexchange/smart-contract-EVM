/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

pragma solidity ^0.8.20;

// To produce super volatile market change for failed cases test
contract TestVolatilePriceSource is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    uint256 public price;
    uint256 public updatedAt;
    uint256 public roundId;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    function getMarkPrice() external view returns (uint256) {
        // offset [0, 27% price]
        uint256 offset = (price * (block.number % 10) * 3e16) / 1e18;
        // 50% price up 50% price down
        return (block.timestamp % 2 == 0) ? price - offset : price + offset;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        roundId++;
        updatedAt = block.timestamp;
        emit AnswerUpdated(SafeCast.toInt256(price), roundId, updatedAt);
    }
}
