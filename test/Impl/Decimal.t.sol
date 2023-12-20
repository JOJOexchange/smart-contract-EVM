/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "../../src/libraries/SignedDecimalMath.sol";
import "forge-std/Test.sol";

contract LibHelper {
    function mul(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 r = SignedDecimalMath.decimalMul(a, b);
        return r;
    }

    function div(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 r = SignedDecimalMath.decimalDiv(a, b);
        return r;
    }

    function remainder(uint256 a, uint256 b) public pure returns (bool) {
        bool r = SignedDecimalMath.decimalRemainder(a, b);
        return r;
    }
}

contract DecimalMathTest is Test {
    LibHelper public helper;

    function setUp() public {
        helper = new LibHelper();
    }

    function testMul() public {
        assertEq(helper.mul(2, 2e18), 4);
    }

    function testDiv() public {
        assertEq(helper.div(2, 2e18), 1);
    }

    function testReminder() public view {
        bool ifRemainder = helper.remainder(2e18, 2e18);
        require(ifRemainder);
    }

    function testReminderFalse() public view {
        bool ifRemainder = helper.remainder(2e18, 3e18);
        require(!ifRemainder);
    }
}
