/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../interfaces/IPerpetual.sol";
import "../interfaces/internal/IDecimalERC20.sol";
import "../libraries/Errors.sol";
import "./Types.sol";

library Operation {
    // ========== events ==========

    event SetFundingRateKeeper(address oldKeeper, address newKeeper);

    event SetInsurance(address oldInsurance, address newInsurance);

    event SetMaxPositionAmount(uint256 oldMaxPositionAmount, uint256 newMaxPositionAmount);

    event SetWithdrawTimeLock(uint256 oldWithdrawTimeLock, uint256 newWithdrawTimeLock);

    event SetOrderSender(address orderSender, bool isValid);

    event SetFastWithdrawalWhitelist(address target, bool isValid);

    event FastWithdrawDisabled(bool disabled);

    event SetOperator(address indexed client, address indexed operator, bool isValid);

    event FundOperatorAllowedChange(
        address indexed client, address indexed operator, uint256 primaryAllowed, uint256 secondaryAllowed
    );

    event SetSecondaryAsset(address secondaryAsset);

    event UpdatePerpRiskParams(address indexed perp, Types.RiskParams param);

    event UpdateFundingRate(address indexed perp, int256 oldRate, int256 newRate);

    // ========== functions ==========

    function setPerpRiskParams(Types.State storage state, address perp, Types.RiskParams calldata param) external {
        if (state.perpRiskParams[perp].isRegistered && !param.isRegistered) {
            // remove perp
            for (uint256 i; i < state.registeredPerp.length;) {
                if (state.registeredPerp[i] == perp) {
                    state.registeredPerp[i] = state.registeredPerp[state.registeredPerp.length - 1];
                    state.registeredPerp.pop();
                }
                unchecked {
                    ++i;
                }
            }
        }
        if (!state.perpRiskParams[perp].isRegistered && param.isRegistered) {
            // new perp
            state.registeredPerp.push(perp);
        }
        require(
            param.liquidationPriceOff + param.insuranceFeeRate <= param.liquidationThreshold, Errors.INVALID_RISK_PARAM
        );
        state.perpRiskParams[perp] = param;
        emit UpdatePerpRiskParams(perp, param);
    }

    function updateFundingRate(address[] calldata perpList, int256[] calldata rateList) external {
        require(perpList.length == rateList.length, Errors.ARRAY_LENGTH_NOT_SAME);
        for (uint256 i = 0; i < perpList.length;) {
            int256 oldRate = IPerpetual(perpList[i]).getFundingRate();
            IPerpetual(perpList[i]).updateFundingRate(rateList[i]);
            emit UpdateFundingRate(perpList[i], oldRate, rateList[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setFundingRateKeeper(Types.State storage state, address newKeeper) external {
        address oldKeeper = state.fundingRateKeeper;
        state.fundingRateKeeper = newKeeper;
        emit SetFundingRateKeeper(oldKeeper, newKeeper);
    }

    function setInsurance(Types.State storage state, address newInsurance) external {
        address oldInsurance = state.insurance;
        state.insurance = newInsurance;
        emit SetInsurance(oldInsurance, newInsurance);
    }

    function setMaxPositionAmount(Types.State storage state, uint256 newMaxPositionAmount) external {
        uint256 oldMaxPositionAmount = state.maxPositionAmount;
        state.maxPositionAmount = newMaxPositionAmount;
        emit SetMaxPositionAmount(oldMaxPositionAmount, newMaxPositionAmount);
    }

    function setWithdrawTimeLock(Types.State storage state, uint256 newWithdrawTimeLock) external {
        uint256 oldWithdrawTimeLock = state.withdrawTimeLock;
        state.withdrawTimeLock = newWithdrawTimeLock;
        emit SetWithdrawTimeLock(oldWithdrawTimeLock, newWithdrawTimeLock);
    }

    function setOrderSender(Types.State storage state, address orderSender, bool isValid) external {
        state.validOrderSender[orderSender] = isValid;
        emit SetOrderSender(orderSender, isValid);
    }

    function setFastWithdrawalWhitelist(Types.State storage state, address target, bool isValid) external {
        state.fastWithdrawalWhitelist[target] = isValid;
        emit SetFastWithdrawalWhitelist(target, isValid);
    }

    function disableFastWithdraw(Types.State storage state, bool disabled) external {
        state.fastWithdrawDisabled = disabled;
        emit FastWithdrawDisabled(disabled);
    }

    function setOperator(Types.State storage state, address client, address operator, bool isValid) external {
        state.operatorRegistry[client][operator] = isValid;
        emit SetOperator(client, operator, isValid);
    }

    function approveFundOperator(
        Types.State storage state,
        address client,
        address operator,
        uint256 primaryAmount,
        uint256 secondaryAmount
    )
        external
    {
        state.primaryCreditAllowed[client][operator] = primaryAmount;
        state.secondaryCreditAllowed[client][operator] = secondaryAmount;
        emit FundOperatorAllowedChange(client, operator, primaryAmount, secondaryAmount);
    }

    function setSecondaryAsset(Types.State storage state, address _secondaryAsset) external {
        require(state.secondaryAsset == address(0), Errors.SECONDARY_ASSET_ALREADY_EXIST);
        require(
            IDecimalERC20(_secondaryAsset).decimals() == IDecimalERC20(state.primaryAsset).decimals(),
            Errors.SECONDARY_ASSET_DECIMAL_WRONG
        );
        state.secondaryAsset = _secondaryAsset;
        emit SetSecondaryAsset(_secondaryAsset);
    }
}
