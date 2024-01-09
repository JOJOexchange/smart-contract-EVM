/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../libraries/Errors.sol";
import "./Types.sol";

library Position {
    // ========== position register ==========

    /// @notice add position when trade or liquidation happen
    /// msg.sender is the perpetual contract
    function _openPosition(Types.State storage state, address trader) internal {
        require(state.openPositions[trader].length < state.maxPositionAmount, Errors.POSITION_AMOUNT_REACH_UPPER_LIMIT);
        state.openPositions[trader].push(msg.sender);
    }

    /// @notice realize pnl and remove position from the registry
    /// msg.sender is the perpetual contract
    function _realizePnl(Types.State storage state, address trader, int256 pnl) internal {
        state.primaryCredit[trader] += pnl;
        state.positionSerialNum[trader][msg.sender] += 1;

        address[] storage positionList = state.openPositions[trader];
        for (uint256 i = 0; i < positionList.length;) {
            if (positionList[i] == msg.sender) {
                positionList[i] = positionList[positionList.length - 1];
                positionList.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }
}
