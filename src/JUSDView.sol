/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.9;

import "./JUSDBankStorage.sol";
import {DecimalMath} from "../lib/DecimalMath.sol";
import "../Interface/IJUSDBank.sol";
import {IPriceChainLink} from "../Interface/IPriceChainLink.sol";

abstract contract JUSDView is JUSDBankStorage, IJUSDBank {
    using DecimalMath for uint256;

    function getReservesList() external view returns (address[] memory) {
        return reservesList;
    }

    function getDepositMaxMintAmount(
        address user
    ) external view returns (uint256) {
        DataTypes.UserInfo storage userInfo = userInfo[user];
        return _maxMintAmount(userInfo);
    }

    function getCollateralMaxMintAmount(
        address collateral,
        uint256 amount
    ) external view returns (uint256 maxAmount) {
        DataTypes.ReserveInfo memory reserve = reserveInfo[collateral];
        return _getMintAmount(reserve, amount, reserve.initialMortgageRate);
    }

    function getMaxWithdrawAmount(
        address collateral,
        address user
    ) external view returns (uint256 maxAmount) {
        DataTypes.UserInfo storage userInfo = userInfo[user];
        uint256 JUSDBorrow = userInfo.t0BorrowBalance.decimalMul(getTRate());
        if (JUSDBorrow == 0) {
            return userInfo.depositBalance[collateral];
        }
        uint256 maxMintAmount = _maxWithdrawAmount(userInfo);
        if (maxMintAmount <= JUSDBorrow) {
            maxAmount = 0;
        } else {
            DataTypes.ReserveInfo memory reserve = reserveInfo[collateral];
            uint256 remainAmount = (maxMintAmount - JUSDBorrow).decimalDiv(
                reserve.initialMortgageRate.decimalMul(
                    IPriceChainLink(reserve.oracle).getAssetPrice()
                )
            );
            remainAmount >= userInfo.depositBalance[collateral]
                ? maxAmount = userInfo.depositBalance[collateral]
                : maxAmount = remainAmount;
        }
    }

    function isAccountSafe(address user) external view returns (bool) {
        DataTypes.UserInfo storage userInfo = userInfo[user];
        return !_isStartLiquidation(userInfo, getTRate());
    }

    function getCollateralPrice(
        address collateral
    ) external view returns (uint256) {
        return IPriceChainLink(reserveInfo[collateral].oracle).getAssetPrice();
    }

    function getIfHasCollateral(
        address from,
        address collateral
    ) external view returns (bool) {
        return userInfo[from].hasCollateral[collateral];
    }

    function getDepositBalance(
        address collateral,
        address from
    ) external view returns (uint256) {
        return userInfo[from].depositBalance[collateral];
    }

    function getBorrowBalance(address from) external view returns (uint256) {
        return (userInfo[from].t0BorrowBalance * getTRate()) / 1e18;
    }

    function getUserCollateralList(
        address from
    ) external view returns (address[] memory) {
        return userInfo[from].collateralList;
    }

    function _getMintAmount(
        DataTypes.ReserveInfo memory reserve,
        uint256 amount,
        uint256 rate
    ) internal view returns (uint256) {
        uint256 depositAmount = IPriceChainLink(reserve.oracle)
            .getAssetPrice()
            .decimalMul(amount)
            .decimalMul(rate);
        if (depositAmount >= reserve.maxColBorrowPerAccount) {
            depositAmount = reserve.maxColBorrowPerAccount;
        }
        return depositAmount;
    }

    function _isAccountSafe(
        DataTypes.UserInfo storage user,
        uint256 tRate
    ) internal view returns (bool) {
        return user.t0BorrowBalance.decimalMul(tRate) <= _maxMintAmount(user);
    }

    function _maxMintAmount(
        DataTypes.UserInfo storage user
    ) internal view returns (uint256) {
        address[] memory collaterals = user.collateralList;
        uint256 maxMintAmount;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            DataTypes.ReserveInfo memory reserve = reserveInfo[collateral];
            if (!reserve.isBorrowAllowed) {
                continue;
            }
            uint256 colMintAmount = _getMintAmount(
                reserve,
                user.depositBalance[collateral],
                reserve.initialMortgageRate
            );
            maxMintAmount += colMintAmount;
        }
        return maxMintAmount;
    }

    function _maxWithdrawAmount(
        DataTypes.UserInfo storage user
    ) internal view returns (uint256) {
        address[] memory collaterals = user.collateralList;
        uint256 maxMintAmount;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            DataTypes.ReserveInfo memory reserve = reserveInfo[collateral];
            if (!reserve.isBorrowAllowed) {
                continue;
            }
            maxMintAmount += IPriceChainLink(reserve.oracle)
                .getAssetPrice()
                .decimalMul(user.depositBalance[collateral])
                .decimalMul(reserve.initialMortgageRate);
        }
        return maxMintAmount;
    }

    /// @notice Determine whether the account is safe by liquidationMortgageRate
    // If the collateral delisted. When calculating the boundary conditions for collateral to be liquidated, treat the value of collateral as 0
    // liquidationMaxMintAmount = sum(depositAmount * price * liquidationMortgageRate)
    function _isStartLiquidation(
        DataTypes.UserInfo storage liquidatedTraderInfo,
        uint256 tRate
    ) internal view returns (bool) {
        uint256 JUSDBorrow = (liquidatedTraderInfo.t0BorrowBalance).decimalMul(
            tRate
        );
        uint256 liquidationMaxMintAmount;
        address[] memory collaterals = liquidatedTraderInfo.collateralList;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            DataTypes.ReserveInfo memory reserve = reserveInfo[collateral];
            if (reserve.isFinalLiquidation) {
                continue;
            }
            liquidationMaxMintAmount += _getMintAmount(
                reserve,
                liquidatedTraderInfo.depositBalance[collateral],
                reserve.liquidationMortgageRate
            );
        }
        return liquidationMaxMintAmount < JUSDBorrow;
    }
}
