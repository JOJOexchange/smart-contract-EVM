/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "./interfaces/IJUSDBank.sol";
import "./interfaces/internal/IPriceSource.sol";
import "./JUSDBankStorage.sol";
import "./libraries/SignedDecimalMath.sol";

abstract contract JUSDView is JUSDBankStorage, IJUSDBank {
    using SignedDecimalMath for uint256;

    function getReservesList() external view returns (address[] memory) {
        return reservesList;
    }

    function getDepositMaxMintAmount(address user) external view returns (uint256) {
        Types.UserInfo storage userInfo = userInfo[user];
        return _maxMintAmount(userInfo);
    }

    function getCollateralMaxMintAmount(address collateral, uint256 amount) external view returns (uint256 maxAmount) {
        Types.ReserveInfo memory reserve = reserveInfo[collateral];
        return _getMintAmount(reserve, amount, reserve.initialMortgageRate);
    }

    function getMaxWithdrawAmount(address collateral, address user) external view returns (uint256 maxAmount) {
        Types.UserInfo storage userInfo = userInfo[user];
        uint256 JUSDBorrow = userInfo.t0BorrowBalance.decimalMul(getTRate());
        if (JUSDBorrow == 0) {
            return userInfo.depositBalance[collateral];
        }
        uint256 maxMintAmount = _maxWithdrawAmount(userInfo);
        if (maxMintAmount <= JUSDBorrow) {
            maxAmount = 0;
        } else {
            Types.ReserveInfo memory reserve = reserveInfo[collateral];
            uint256 remainAmount = (maxMintAmount - JUSDBorrow).decimalDiv(
                reserve.initialMortgageRate.decimalMul(IPriceSource(reserve.oracle).getAssetPrice())
            );
            remainAmount >= userInfo.depositBalance[collateral]
                ? maxAmount = userInfo.depositBalance[collateral]
                : maxAmount = remainAmount;
        }
    }

    function isAccountSafe(address user) external view returns (bool) {
        Types.UserInfo storage userInfo = userInfo[user];
        return !_isStartLiquidation(userInfo, getTRate());
    }

    function getCollateralPrice(address collateral) external view returns (uint256) {
        return IPriceSource(reserveInfo[collateral].oracle).getAssetPrice();
    }

    function getIfHasCollateral(address from, address collateral) external view returns (bool) {
        return userInfo[from].hasCollateral[collateral];
    }

    function getDepositBalance(address collateral, address from) external view returns (uint256) {
        return userInfo[from].depositBalance[collateral];
    }

    function getBorrowBalance(address from) external view returns (uint256) {
        return (userInfo[from].t0BorrowBalance * getTRate()) / 1e18;
    }

    function getUserCollateralList(address from) external view returns (address[] memory) {
        return userInfo[from].collateralList;
    }

    function _getMintAmount(
        Types.ReserveInfo memory reserve,
        uint256 amount,
        uint256 rate
    )
        internal
        view
        returns (uint256)
    {
        uint256 depositAmount = IPriceSource(reserve.oracle).getAssetPrice().decimalMul(amount).decimalMul(rate);
        if (depositAmount >= reserve.maxColBorrowPerAccount) {
            depositAmount = reserve.maxColBorrowPerAccount;
        }
        return depositAmount;
    }

    function _isAccountSafe(Types.UserInfo storage user, uint256 tRate) internal view returns (bool) {
        return user.t0BorrowBalance.decimalMul(tRate) <= _maxMintAmount(user);
    }

    function _maxMintAmount(Types.UserInfo storage user) internal view returns (uint256) {
        address[] memory collaterals = user.collateralList;
        uint256 maxMintAmount;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            Types.ReserveInfo memory reserve = reserveInfo[collateral];
            if (!reserve.isBorrowAllowed) {
                continue;
            }
            uint256 colMintAmount =
                _getMintAmount(reserve, user.depositBalance[collateral], reserve.initialMortgageRate);
            maxMintAmount += colMintAmount;
        }
        return maxMintAmount;
    }

    function _maxWithdrawAmount(Types.UserInfo storage user) internal view returns (uint256) {
        address[] memory collaterals = user.collateralList;
        uint256 maxMintAmount;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            Types.ReserveInfo memory reserve = reserveInfo[collateral];
            if (!reserve.isBorrowAllowed) {
                continue;
            }
            maxMintAmount += IPriceSource(reserve.oracle).getAssetPrice().decimalMul(user.depositBalance[collateral])
                .decimalMul(reserve.initialMortgageRate);
        }
        return maxMintAmount;
    }

    /// @notice Determine whether the account is safe by liquidationMortgageRate
    // liquidationMaxMintAmount = sum(depositAmount * price * liquidationMortgageRate)
    function _isStartLiquidation(
        Types.UserInfo storage liquidatedTraderInfo,
        uint256 tRate
    )
        internal
        view
        returns (bool)
    {
        uint256 JUSDBorrow = (liquidatedTraderInfo.t0BorrowBalance).decimalMul(tRate);
        uint256 liquidationMaxMintAmount;
        address[] memory collaterals = liquidatedTraderInfo.collateralList;
        for (uint256 i; i < collaterals.length; i = i + 1) {
            address collateral = collaterals[i];
            Types.ReserveInfo memory reserve = reserveInfo[collateral];
            if (reserve.isFinalLiquidation) {
                continue;
            }
            liquidationMaxMintAmount += _getMintAmount(
                reserve, liquidatedTraderInfo.depositBalance[collateral], reserve.liquidationMortgageRate
            );
        }
        return liquidationMaxMintAmount < JUSDBorrow;
    }
}
