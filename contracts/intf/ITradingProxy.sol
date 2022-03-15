/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

interface ITradingProxy {
    function isValidPerpetualOperator(address o) external returns (bool);
}
