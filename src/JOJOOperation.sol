/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDealer.sol";
import "./libraries/Errors.sol";
import "./libraries/Operation.sol";
import "./libraries/Types.sol";
import "./JOJOStorage.sol";

/// @notice Owner-only functions
abstract contract JOJOOperation is JOJOStorage, IDealer {
    using SafeERC20 for IERC20;

    // ========== params updates ==========

    /// @inheritdoc IDealer
    function updateFundingRate(
        address[] calldata perpList,
        int256[] calldata rateList
    )
        external
        onlyFundingRateKeeper
    {
        Operation.updateFundingRate(perpList, rateList);
    }

    /// @notice Set risk parameters for a perpetual market.
    /// @param param market will be ready to trade if param.isRegistered value is true.
    /// This market will not be opened if param.isRegistered value is false.
    function setPerpRiskParams(address perp, Types.RiskParams calldata param) external onlyOwner {
        Operation.setPerpRiskParams(state, perp, param);
    }

    function setFundingRateKeeper(address newKeeper) external onlyOwner {
        Operation.setFundingRateKeeper(state, newKeeper);
    }

    function setInsurance(address newInsurance) external onlyOwner {
        Operation.setInsurance(state, newInsurance);
    }

    function setMaxPositionAmount(uint256 newMaxPositionAmount) external onlyOwner {
        Operation.setMaxPositionAmount(state, newMaxPositionAmount);
    }

    function setWithdrawTimeLock(uint256 newWithdrawTimeLock) external onlyOwner {
        Operation.setWithdrawTimeLock(state, newWithdrawTimeLock);
    }

    function setOrderSender(address orderSender, bool isValid) external onlyOwner {
        Operation.setOrderSender(state, orderSender, isValid);
    }

    function setFastWithdrawalWhitelist(address target, bool isValid) external onlyOwner {
        Operation.setFastWithdrawalWhitelist(state, target, isValid);
    }

    function disableFastWithdraw(bool disabled) external onlyOwner {
        Operation.disableFastWithdraw(state, disabled);
    }

    /// @notice Secondary asset can only be set once.
    /// Secondary asset must have the same decimal with primary asset.
    function setSecondaryAsset(address _secondaryAsset) external onlyOwner {
        Operation.setSecondaryAsset(state, _secondaryAsset);
    }
}
