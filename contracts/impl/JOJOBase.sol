/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/Errors.sol";

contract JOJOBase is Ownable, ReentrancyGuard {
    address underlyingAsset; // IERC20
    address insurance;

    struct riskParams {
        // liquidate when netValue/exposure < liquidationThreshold
        // the lower liquidationThreshold, leverage multiplier higher
        uint256 liquidationThreshold;
        uint256 liquidationPriceOff;
        uint256 insuranceFeeRate;
        int256 fundingRatio;
        address markPriceSource;
    }
    mapping(address => bool) public perpRegister;
    mapping(address => riskParams) public perpRiskParams;

    modifier perpRegistered(address perp) {
        require(perpRegister[perp], Errors.PERP_NOT_REGISTERED);
        _;
    }

    modifier perpNotRegistered(address perp) {
        require(!perpRegister[perp], Errors.PERP_ALREADY_REGISTERED);
        _;
    }

    function getFundingRatio(address perpetualAddress)
        external
        view
        perpRegistered(perpetualAddress)
        returns (int256)
    {
        return perpRiskParams[perpetualAddress].fundingRatio;
    }

    function setFundingRatio(
        address[] calldata perpList,
        int256[] calldata ratioList
    ) external onlyOwner {
        for (uint256 i = 0; i < perpList.length; i++) {
            riskParams storage param = perpRiskParams[perpList[i]];
            param.fundingRatio = ratioList[i];
        }
    }

    function registerNewPerp(address perp, riskParams calldata param)
        external
        onlyOwner
        perpNotRegistered(perp)
    {
        perpRiskParams[perp] = param;
    }
}
