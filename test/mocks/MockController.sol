/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@moonwell/MToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockController {
    address public well;
    address public usdc;

    constructor(address _well, address _usdc) {
        well = _well;
        usdc = _usdc;
    }
    // add this to be excluded from coverage report
    function test() public { }

    function claimReward(address[] memory holders, MToken[] memory) external {
        address holder = holders[0];
        IERC20(well).transfer(holder, 1e18);
        IERC20(usdc).transfer(holder, 1e6);
    }
}
