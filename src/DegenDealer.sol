/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DegenDealer is Ownable {
    struct PositionInfo {
        address trader;
        int256 paperAmount;
        int256 creditAmount;
        int256 fee;
        int256 pnl;
        string perp;
    }

    address public primaryAsset;

    using SafeERC20 for IERC20;

    event DegenDeposit(address account, uint256 amount);
    event DegenWithdraw(address account, uint256 amount);
    event PositionFinalizeLog(
        address indexed trader, int256 paperAmount, int256 creditAmount, int256 fee, int256 pnl, string perp
    );

    constructor(address _primaryAsset) {
        primaryAsset = _primaryAsset;
    }

    function deposit(address account, uint256 amount) external {
        IERC20(primaryAsset).safeTransferFrom(msg.sender, address(this), amount);
        emit DegenDeposit(account, amount);
    }

    function withdraw(address account, uint256 amount) external onlyOwner {
        IERC20(primaryAsset).safeTransfer(account, amount);
        emit DegenWithdraw(account, amount);
    }

    function batchUpdatePosition(PositionInfo[] memory positionDatas) public onlyOwner {
        for (uint256 i; i < positionDatas.length; i++) {
            PositionInfo memory position = positionDatas[i];
            emit PositionFinalizeLog(
                position.trader, position.paperAmount, position.creditAmount, position.fee, position.pnl, position.perp
            );
        }
    }
}
