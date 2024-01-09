/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";

// Check dealer's view function
contract JOJOViewTest is Checkers {
    function testJOJOView() public {
        bool ifOrderValid = jojoDealer.isOrderSenderValid(address(this));
        assertEq(ifOrderValid, true);
        bool ifWithdrawValid = jojoDealer.isFastWithdrawalValid(address(this));
        assertEq(ifWithdrawValid, false);

        (uint256 primaryCreditAllowed,) = jojoDealer.isCreditAllowed(traders[0], address(this));
        assertEq(primaryCreditAllowed, 0);

        jojoDealer.getOrderFilledAmount(Types.ORDER_TYPEHASH);
        jojoDealer.getRequestWithdrawCallData(address(this), 0, 0);
        jojoDealer.getExecuteWithdrawCallData(address(this), address(this), false, "");
        jojoDealer.isIMSafe(address(this));
    }

    function testVersion() public view {
        jojoDealer.version();
    }
}
