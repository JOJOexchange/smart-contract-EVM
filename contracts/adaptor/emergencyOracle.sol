/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/access/Ownable.sol";

contract EmergencyOracle is Ownable{
    uint256 public price;
    uint256 public roundId;
    string public description;

    // Align with chainlink
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    constructor(string memory _description) {
        description = _description;
    }

    function getMarkPrice() external view returns (uint256) {
        return price;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit AnswerUpdated(int256(price), roundId, block.timestamp);
    }
}