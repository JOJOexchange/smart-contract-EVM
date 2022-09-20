/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract uniswapV3Adaptor {

    event Gas(uint256);

    address uniswapV3Pool = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    function getPrice()
    external
    view
    returns (uint256 diff)
    {
        uint256 u0 = gasleft();
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Pool);
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 2000;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        int24 averageTick = int24((tickCumulatives[1] - tickCumulatives[0]) / 3600);
        TickMath.getSqrtRatioAtTick(averageTick);
        uint256 u1 = gasleft();
        return u0-u1;
    }
}
