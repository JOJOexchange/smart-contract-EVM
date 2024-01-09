/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

contract MockUniswapOracle {
    // add this to be excluded from coverage report
    function test() public { }

    function quoteSpecificPoolsWithTimePeriod(
        uint128,
        address,
        address,
        address[] calldata,
        uint32
    )
        external
        pure
        returns (uint256 quoteAmount)
    {
        return 1010e6;
    }
}
