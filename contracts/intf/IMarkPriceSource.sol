/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

// return mark price

interface IMarkPriceSource {
    function getMarkPrice() external returns (uint256 price);
}
