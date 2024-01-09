/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";

contract Checkers is TradingInit {
    // add this to be excluded from coverage report
    function testC() public { }

    struct Credit {
        int256 primaryCredit;
        uint256 secondaryCredit;
        uint256 pendingPrimaryWithdraw;
        uint256 pendingSecondaryWithdraw;
        uint256 executionTimestamp;
    }

    struct Balance {
        uint256 paper;
        uint256 credit;
    }

    function checkCredit(address trader, int256 primary, uint256 secondary) public returns (Credit memory credit) {
        (
            int256 primaryCredit,
            uint256 secondaryCredit,
            uint256 pendingPrimaryWithdraw,
            uint256 pendingSecondaryWithdraw,
            uint256 executionTimestamp
        ) = jojoDealer.getCreditOf(trader);

        credit.primaryCredit = primaryCredit;
        credit.secondaryCredit = secondaryCredit;
        credit.pendingPrimaryWithdraw = pendingPrimaryWithdraw;
        credit.pendingSecondaryWithdraw = pendingSecondaryWithdraw;
        credit.executionTimestamp = executionTimestamp;

        assertEq(credit.primaryCredit, primary);
        assertEq(credit.secondaryCredit, secondary);
    }
}
