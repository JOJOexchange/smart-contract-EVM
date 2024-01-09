/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BatchTransferERC20 is Ownable {
    using SafeERC20 for IERC20;

    function batchTransfer(address token, address[] memory receivers, uint256[] memory amounts) public onlyOwner {
        require(receivers.length == amounts.length, "PARAM_LENGTH_INVALID");
        for (uint256 i = 0; i < receivers.length; i++) {
            IERC20(token).safeTransfer(receivers[i], amounts[i]);
        }
    }
}
