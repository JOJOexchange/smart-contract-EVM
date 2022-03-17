/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "./JOJOTrading.sol";

contract JOJODealer is JOJOTrading {
    // Construct
    constructor(
        address _underlyingAsset,
        address _orderValidator
    ) JOJOTrading() {
        underlyingAsset = _underlyingAsset;
        orderValidator = _orderValidator;
    }
}
