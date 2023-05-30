/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../intf/IDealer.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IWETH} from "../intf/IWETH.sol";

contract DepositStableCoinToDealer is Ownable{

    using SafeERC20 for IERC20;

    address public immutable JOJODealer;
    address public immutable USDC;
    mapping(address => bool) public whiteListContract;
    address public WETH;

    constructor(
        address _JOJODealer,
        address _USDC,
        address _WETH
    ) {
        JOJODealer = _JOJODealer;
        USDC = _USDC;
        WETH = _WETH;
    }

    function setWhiteListContract(address targetContract, bool isValid) onlyOwner public {
        whiteListContract[targetContract] = isValid;
    }

    function depositStableCoin(
        address asset,
        uint256 amount,
        address to,
        bytes calldata param,
        uint256 minReceive
    ) external payable{
        if (asset == WETH && msg.value >= amount) {
            IWETH(WETH).deposit{value: amount}();
            IWETH(WETH).transfer(address(this), amount);
        }
        else {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
        (address approveTarget, address swapTarget, bytes memory data) = abi
        .decode(param, (address, address, bytes));
        require(whiteListContract[approveTarget], "approve target is not in the whitelist");
        require(whiteListContract[swapTarget], "swap target is not in the whitelist");
        // if usdt
        IERC20(asset).approve(approveTarget, 0);
        IERC20(asset).approve(approveTarget, amount);
        (bool success, ) = swapTarget.call(data);
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        uint256 USDCAmount = IERC20(USDC).balanceOf(address(this));
        require(USDCAmount >= minReceive,"receive amount is too small");
        IERC20(USDC).approve(JOJODealer, USDCAmount);
        IDealer(JOJODealer).deposit(USDCAmount, 0, to);
    }
}
