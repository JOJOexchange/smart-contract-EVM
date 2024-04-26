/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface MTokenInterface {
    function exchangeRateStored() external view returns (uint);
}

contract MoonwellOracle {
    uint256 public price;
    address public immutable source;
    string public description;

    constructor(string memory _description, address _source) {
        description = _description;
        source = _source;
    }

    function getAssetPrice() external view returns (uint256) {
        uint256 rate = MTokenInterface(source).exchangeRateStored();
        return rate;
    }
}
