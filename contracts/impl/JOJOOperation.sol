/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JOJOStorage.sol";
import "../utils/Errors.sol";
import "../lib/Types.sol";
import "../lib/Liquidation.sol";

/// @notice Owner-only functions
contract JOJOOperation is JOJOStorage {
    using SafeERC20 for IERC20;

    // ========== events ==========

    event HandleBadDebt(
        address indexed liquidatedTrader,
        int256 primaryCredit,
        uint256 secondaryCredit
    );

    event UpdateFundingRate(
        address indexed perp,
        int256 oldRate,
        int256 newRate
    );

    event UpdatePerpRiskParams(address indexed perp, Types.RiskParams param);

    event SetInsurance(address oldInsurance, address newInsurance);

    event SetWithdrawTimeLock(
        uint256 oldWithdrawTimeLock,
        uint256 newWithdrawTimeLock
    );

    event SetOrderSender(address orderSender, bool isValid);

    // ========== balance related ==========

    /// @notice Transfer all bad debt to insurance account, including
    /// primary and secondary balance.
    function handleBadDebt(address liquidatedTrader) external onlyOwner {
        require(
            !Liquidation._isSafe(state, liquidatedTrader),
            Errors.ACCOUNT_IS_SAFE
        );
        require(
            state.openPositions[liquidatedTrader].length == 0,
            Errors.TRADER_STILL_IN_LIQUIDATION
        );
        int256 primaryCredit = state.primaryCredit[liquidatedTrader];
        uint256 secondaryCredit = state.secondaryCredit[liquidatedTrader];
        state.primaryCredit[state.insurance] += primaryCredit;
        state.secondaryCredit[state.insurance] += secondaryCredit;
        state.primaryCredit[liquidatedTrader] = 0;
        state.secondaryCredit[liquidatedTrader] = 0;
        emit HandleBadDebt(liquidatedTrader, primaryCredit, secondaryCredit);
    }

    // ========== params updates ==========

    function updateFundingRate(
        address[] calldata perpList,
        int256[] calldata rateList
    ) external onlyOwner {
        for (uint256 i = 0; i < perpList.length; i++) {
            Types.RiskParams storage param = state.perpRiskParams[perpList[i]];
            int256 oldRate = param.fundingRate;
            param.fundingRate = rateList[i];
            emit UpdateFundingRate(perpList[i], oldRate, rateList[i]);
        }
    }

    /// @notice Set risk parameters for a perpetual market.
    /// @param param market will be ready to trade if param.isRegistered value is true.
    /// This market will not be opened if param.isRegistered value is false.
    function setPerpRiskParams(address perp, Types.RiskParams calldata param)
        external
        onlyOwner
    {
        if (state.perpRiskParams[perp].isRegistered && !param.isRegistered) {
            // remove perp
            for (uint256 i; i < state.registeredPerp.length; i++) {
                if (state.registeredPerp[i] == perp) {
                    state.registeredPerp[i] = state.registeredPerp[
                        state.registeredPerp.length - 1
                    ];
                    state.registeredPerp.pop();
                }
            }
        }
        if (!state.perpRiskParams[perp].isRegistered && param.isRegistered) {
            // new perp
            state.registeredPerp.push(perp);
        }
        require(
            param.liquidationThreshold < 10**18 &&
                param.liquidationPriceOff < param.liquidationThreshold &&
                param.insuranceFeeRate < param.liquidationThreshold,
            Errors.INVALID_RISK_PARAM
        );
        state.perpRiskParams[perp] = param;
        emit UpdatePerpRiskParams(perp, param);
    }

    function setInsurance(address newInsurance) external onlyOwner {
        address oldInsurance = state.insurance;
        state.insurance = newInsurance;
        emit SetInsurance(oldInsurance, newInsurance);
    }

    function setWithdrawTimeLock(uint256 newWithdrawTimeLock)
        external
        onlyOwner
    {
        uint256 oldWithdrawTimeLock = state.withdrawTimeLock;
        state.withdrawTimeLock = newWithdrawTimeLock;
        emit SetWithdrawTimeLock(oldWithdrawTimeLock, newWithdrawTimeLock);
    }

    function setOrderSender(address orderSender, bool isValid)
        external
        onlyOwner
    {
        state.validOrderSender[orderSender] = isValid;
        emit SetOrderSender(orderSender, isValid);
    }

    /// @notice Secondary asset can only be set once.
    function setSecondaryAsset(address _secondaryAsset) external onlyOwner {
        require(
            state.secondaryAsset == address(0),
            Errors.SECONDARY_ASSET_ALREASY_EXIST
        );
        state.secondaryAsset = _secondaryAsset;
    }
}
