/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SupportsSwap {

    using SafeERC20 for IERC20;
    address USDC;

    constructor(address _USDC) {
        USDC = _USDC;
    }

    function swap(uint256 amount, address token) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(USDC).safeTransfer(msg.sender, amount);
    }
}
