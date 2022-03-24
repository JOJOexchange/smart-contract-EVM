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

contract JOJOOperation is JOJOStorage {
    using SafeERC20 for IERC20;

    function setVirtualCredit(address trader, uint256 amount)
        external
        onlyOwner
    {
        state.virtualCredit[trader] = amount;
    }

    function handleBadDebt(address liquidatedTrader) external onlyOwner {
        require(
            !Liquidation._isSafe(state, liquidatedTrader),
            Errors.ACCOUNT_IS_SAFE
        );
        require(
            state.openPositions[liquidatedTrader].length == 0,
            Errors.TRADER_STILL_IN_LIQUIDATION
        );
        state.trueCredit[state.insurance] += state.trueCredit[liquidatedTrader];
        state.trueCredit[liquidatedTrader] = 0;
        state.virtualCredit[liquidatedTrader] = 0;
    }

    function setFundingRatio(
        address[] calldata perpList,
        int256[] calldata ratioList
    ) external onlyOwner {
        for (uint256 i = 0; i < perpList.length; i++) {
            Types.RiskParams storage param = state.perpRiskParams[perpList[i]];
            param.fundingRatio = ratioList[i];
        }
    }

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
        state.perpRiskParams[perp] = param;
    }

    function setInsurance(address newInsurance) external onlyOwner {
        state.insurance = newInsurance;
    }

    function setWithdrawTimeLock(uint256 newTimeLock) external onlyOwner {
        state.withdrawTimeLock = newTimeLock;
    }
}
