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
        string name;
    }
    mapping(address => riskParams) public perpRiskParams;

    function getFundingRatio(address perpetualAddress)
        external
        view
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

    function registerPerp(address perp, riskParams calldata param)
        external
        onlyOwner
    {
        perpRiskParams[perp] = param;
    }

    function setInsurance(address newInsurance) external onlyOwner {
        insurance = newInsurance;
    }
}
