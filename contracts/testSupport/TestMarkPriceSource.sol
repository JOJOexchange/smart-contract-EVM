/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

contract TestMarkPriceSource is Ownable {
    uint256 public price;

    function getMarkPrice() external view returns (uint256) {
        return price;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
    }
}
