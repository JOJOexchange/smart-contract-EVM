/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

contract TestTradingProxy is Ownable {
    mapping(address => bool) operator;

    constructor() Ownable(){
        operator[msg.sender] = true;
    }

    function isValidPerpetualOperator(address o) external view returns (bool) {
        return operator[o];
    }

    function setOperator(address o, bool can) external onlyOwner {
        operator[o] = can;
    }
}
