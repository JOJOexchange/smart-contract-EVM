/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;


import "../FundingRateArbitrage.sol";

contract EarnOracle {

    address public arbitrage;

    constructor(address _arbitrage) {
        arbitrage = _arbitrage;
    }

    function getMarkPrice() external view returns (uint256) {
        return FundingRateArbitrage(arbitrage).getIndex();
    }

    function getAssetPrice() external view returns (uint256) {
        return FundingRateArbitrage(arbitrage).getIndex();
    }

}
