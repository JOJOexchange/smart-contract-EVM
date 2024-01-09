/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

contract ConstOracle {
    uint256 public immutable price;

    constructor(uint256 _price) {
        price = _price;
    }

    function getMarkPrice() external view returns (uint256) {
        return price;
    }
}
