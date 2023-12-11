/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
interface IChainlink {
    function latestAnswer() external view returns (int256 answer);
}

contract MockRate is Ownable {

    uint256 public rate;
    uint256 public roundId;

    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    function latestRate() external view returns (uint256 price) {
        return rate;
    }

    function setLatestRate(uint256 newRate) external onlyOwner {
        rate = newRate;
        emit AnswerUpdated(SafeCast.toInt256(rate), roundId, block.timestamp);
        roundId += 1;
    }
}
