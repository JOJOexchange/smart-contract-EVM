/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "./JOJOView.sol";
import "./JOJOExternal.sol";
import "./JOJOOperation.sol";

contract JOJODealer is JOJOView, JOJOExternal, JOJOOperation {
    constructor(address _underlyingAsset, address _orderValidator) Ownable() {
        state.underlyingAsset = _underlyingAsset;
        state.orderValidator = _orderValidator;
        state.domainSeparator = EIP712._buildDomainSeparator("JOJO", "1");
    }
}
