/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "../../src/libraries/SignedDecimalMath.sol";
import "../../src/libraries/EIP712.sol";
import "forge-std/Test.sol";

pragma solidity ^0.8.20;

// Check dealer's internal library
contract InternalLibraryTest {
    function mul(int256 a, int256 b) public pure {
        SignedDecimalMath.decimalMul(a, b);
    }

    function div(int256 a, int256 b) public pure {
        SignedDecimalMath.decimalDiv(a, b);
    }

    function abs(int256 a) public pure {
        SignedDecimalMath.abs(a);
    }

    function Remainder(uint256 a, uint256 b) public pure {
        SignedDecimalMath.decimalRemainder(a, b);
    }

    function tEIP712(string memory name, string memory version, address verifyingContract) public view {
        EIP712._buildDomainSeparator(name, version, verifyingContract);
    }
}

contract DecimalMathTest is Test {
    InternalLibraryTest public helper;

    function setUp() public {
        helper = new InternalLibraryTest();
    }

    function testMul() public view {
        helper.mul(-2, -2e18);
    }

    function testDiv() public view {
        helper.div(-2, -2e18);
    }

    function testAbs() public view {
        helper.abs(-2);
    }

    function testRemainder() public view {
        helper.Remainder(3, 4);
    }

    function testRemainder2() public view {
        helper.Remainder(3, 4e18);
    }

    function testEIP712() public view {
        helper.tEIP712("Hey", "Hey", address(this));
    }
}
