/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

/// @notice JUSDExchange is an exchange system that allow users to exchange USDC to JUSD in 1:1
interface IJUSDExchange {
    /// @notice in buyJUSD function, users can buy JUSD using USDC
    /// @param amount: the amount of JUSD the users want to buy
    /// @param to: the JUSD transfer to which address
    function buyJUSD(uint256 amount, address to) external;
}
