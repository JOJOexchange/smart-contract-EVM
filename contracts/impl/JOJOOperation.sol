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
import "../lib/Operation.sol";

/// @notice Owner-only functions
contract JOJOOperation is JOJOStorage {
    using SafeERC20 for IERC20;

    // ========== params updates ==========

    /// @notice Update multiple funding rate at once.
    /// Can only be called by funding rate keeper.
    function updateFundingRate(
        address[] calldata perpList,
        int256[] calldata rateList
    ) external {
        Operation.updateFundingRate(state, perpList, rateList);
    }

    /// @notice Set risk parameters for a perpetual market.
    /// @param param market will be ready to trade if param.isRegistered value is true.
    /// This market will not be opened if param.isRegistered value is false.
    function setPerpRiskParams(address perp, Types.RiskParams calldata param)
        external
        onlyOwner
    {
        Operation.setPerpRiskParams(state, perp, param);
    }

    function setFundingRateKeeper(address newKeeper) external onlyOwner {
        Operation.setFundingRateKeeper(state, newKeeper);
    }

    function setInsurance(address newInsurance) external onlyOwner {
        Operation.setInsurance(state, newInsurance);
    }

    function setWithdrawTimeLock(uint256 newWithdrawTimeLock)
        external
        onlyOwner
    {
        Operation.setWithdrawTimeLock(state, newWithdrawTimeLock);
    }

    function setOrderSender(address orderSender, bool isValid)
        external
        onlyOwner
    {
        Operation._setOrderSender(state, orderSender, isValid);
    }

    /// @notice Secondary asset can only be set once.
    function setSecondaryAsset(address _secondaryAsset) external onlyOwner {
        Operation.setSecondaryAsset(state, _secondaryAsset);
    }
}
