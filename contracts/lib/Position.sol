/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "../utils/Errors.sol";
import "./Types.sol";

library Position {

    // ========== position register ==========

    /// @notice add position when trade or liquidation happen
    function _openPosition(
        Types.State storage state,
        address perp,
        address trader
    ) internal {
        if (!state.hasPosition[trader][perp]) {
            state.hasPosition[trader][perp] = true;
            state.openPositions[trader].push(perp);
        }
    }

    /// @notice realize pnl and remove position from the registry
    function _realizePnl(
        Types.State storage state,
        address trader,
        int256 pnl
    ) internal {
        state.hasPosition[trader][msg.sender] = false;
        state.primaryCredit[trader] += pnl;
        state.positionSerialNum[trader][msg.sender] += 1;

        address[] storage positionList = state.openPositions[trader];
        for (uint256 i = 0; i < positionList.length; i++) {
            if (positionList[i] == msg.sender) {
                positionList[i] = positionList[positionList.length - 1];
                positionList.pop();
                break;
            }
        }
    }
}
