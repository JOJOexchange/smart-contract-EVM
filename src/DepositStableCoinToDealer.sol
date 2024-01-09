/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDealer.sol";

interface IWETH {
    function deposit() external payable;
}

contract DepositStableCoinToDealer is Ownable {
    using SafeERC20 for IERC20;

    address public immutable jojoDealer;
    address public immutable usdc;
    address public immutable weth;
    mapping(address => bool) public whiteListContract;

    constructor(address _JOJODealer, address _usdc, address _weth) {
        jojoDealer = _JOJODealer;
        usdc = _usdc;
        weth = _weth;
    }

    function setWhiteListContract(address targetContract, bool isValid) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function depositStableCoin(
        address asset,
        uint256 amount,
        address to,
        bytes calldata param,
        uint256 minReceive
    )
        external
        payable
    {
        if (asset == weth && msg.value == amount) {
            IWETH(weth).deposit{ value: amount }();
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
        (address approveTarget, address swapTarget, bytes memory data) = abi.decode(param, (address, address, bytes));
        require(whiteListContract[approveTarget], "approve target is not in the whitelist");
        require(whiteListContract[swapTarget], "swap target is not in the whitelist");
        // if usdt
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

        uint256 usdcAmount = IERC20(usdc).balanceOf(address(this));
        require(usdcAmount >= minReceive, "receive amount is too small");
        IERC20(usdc).approve(jojoDealer, usdcAmount);
        IDealer(jojoDealer).deposit(usdcAmount, 0, to);
    }
}
