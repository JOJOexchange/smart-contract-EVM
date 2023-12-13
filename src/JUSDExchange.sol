/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^^0.8.9;

import "../Interface/IJUSDExchange.sol";
import "../utils/JUSDError.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@JOJO/contracts/intf/IDealer.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// the exchange rate is 1:1
contract JUSDExchange is IJUSDExchange, Ownable {
    using SafeERC20 for IERC20;

    //        primary asset address
    address public immutable primaryAsset;
    address public immutable JUSD;

    bool public isExchangeOpen;

    //    ---------------event-----------------
    event BuyJUSD(uint256 amount, address indexed to, address indexed payer);

    //    --------------------operator-----------------------

    constructor(address _USDC, address _JUSD) {
        primaryAsset = _USDC;
        JUSD = _JUSD;
        isExchangeOpen = true;
    }

    function closeExchange() external onlyOwner {
        isExchangeOpen = false;
    }

    function openExchange() external onlyOwner {
        isExchangeOpen = true;
    }

    function buyJUSD(uint256 amount, address to) external {
        require(isExchangeOpen, JUSDErrors.NOT_ALLOWED_TO_EXCHANGE);
        IERC20(primaryAsset).safeTransferFrom(msg.sender, owner(), amount);
        IERC20(JUSD).safeTransfer(to, amount);
        emit BuyJUSD(amount, to, msg.sender);
    }

    function refundJUSD(uint256 amount) external onlyOwner {
        IERC20(JUSD).safeTransfer(msg.sender, amount);
    }
}
