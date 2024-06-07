/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IPriceSource.sol";
import "../token/JWrapMUSDC.sol";


contract MoonwellJwrapUSDCOracle {
    address public immutable source;
    address public immutable jwrapMUSDC;
    string public description;

    constructor(address _source, string memory _description, address _jwrapMUSDC) {
        description = _description;
        source = _source;
        jwrapMUSDC = _jwrapMUSDC;
    }

    function getAssetPrice() external view returns (uint256) {
        uint256 rate = IPriceSource(source).getAssetPrice();
        uint256 index = JWrapMUSDC(jwrapMUSDC).getIndex();
        return rate * index / 1e18;
    }
}
