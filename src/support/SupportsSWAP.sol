/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPriceChainLink} from "../Interface/IPriceChainLink.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SupportsSWAP {
    using SafeERC20 for IERC20;
    address USDC;
    mapping(address => address) tokenPrice;

    constructor(address _USDC, address _ETH, address _price) {
        USDC = _USDC;
        tokenPrice[_ETH] = _price;
    }

    function addTokenPrice(address token, address price) public {
        tokenPrice[token] = price;
    }

    function swap(uint256 amount, address token) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 value = (amount *
            IPriceChainLink(tokenPrice[token]).getAssetPrice()) / 1e18;
        IERC20(USDC).safeTransfer(msg.sender, value);
    }

    function getSwapData(
        uint256 amount,
        address token
    ) external pure returns (bytes memory) {
        return abi.encodeWithSignature("swap(uint256,address)", amount, token);
    }
}
