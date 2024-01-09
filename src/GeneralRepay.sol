/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IJUSDBank.sol";
import "./interfaces/IJUSDExchange.sol";

pragma solidity ^0.8.20;

contract GeneralRepay is Ownable {
    using SafeERC20 for IERC20;

    address public immutable USDC;
    address public immutable JUSD;
    address public jusdBank;
    address public jusdExchange;
    mapping(address => bool) public whiteListContract;

    constructor(address _jusdBank, address _jusdExchange, address _USDC, address _JUSD) {
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        USDC = _USDC;
        JUSD = _JUSD;
    }

    function setWhiteListContract(address targetContract, bool isValid) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function repayJUSD(address asset, uint256 amount, address to, bytes memory param) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        uint256 minReceive;
        if (asset != USDC) {
            (address approveTarget, address swapTarget, uint256 minAmount, bytes memory data) =
                abi.decode(param, (address, address, uint256, bytes));
            require(whiteListContract[approveTarget], "approve target is not in the whitelist");
            require(whiteListContract[swapTarget], "swap target is not in the whitelist");
            IERC20(asset).safeApprove(approveTarget, 0);
            IERC20(asset).safeApprove(approveTarget, amount);
            (bool success,) = swapTarget.call(data);
            if (success == false) {
                assembly {
                    let ptr := mload(0x40)
                    let size := returndatasize()
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            }
            minReceive = minAmount;
        }
        uint256 USDCAmount = IERC20(USDC).balanceOf(address(this));
        require(USDCAmount >= minReceive, "receive amount is too small");
        uint256 JUSDAmount = USDCAmount;
        uint256 borrowBalance = IJUSDBank(jusdBank).getBorrowBalance(to);
        if (USDCAmount <= borrowBalance) {
            IERC20(USDC).approve(jusdExchange, USDCAmount);
            IJUSDExchange(jusdExchange).buyJUSD(USDCAmount, address(this));
        } else {
            IERC20(USDC).approve(jusdExchange, borrowBalance);
            IJUSDExchange(jusdExchange).buyJUSD(borrowBalance, address(this));
            IERC20(USDC).safeTransfer(msg.sender, USDCAmount - borrowBalance);
            JUSDAmount = borrowBalance;
        }
        IERC20(JUSD).approve(jusdBank, JUSDAmount);
        IJUSDBank(jusdBank).repay(JUSDAmount, to);
    }
}
