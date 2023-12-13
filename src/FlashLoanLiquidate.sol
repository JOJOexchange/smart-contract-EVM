/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.9;

import "../../../src/Interface/IJUSDBank.sol";
import "../../../src/Interface/IJUSDExchange.sol";
import "../../../src/Interface/IFlashLoanReceive.sol";
import {DecimalMath} from "../../lib/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceChainLink} from "../../Interface/IPriceChainLink.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlashLoanLiquidate is IFlashLoanReceive, Ownable {
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    address public jusdBank;
    address public jusdExchange;
    address public immutable USDC;
    address public immutable JUSD;
    address public insurance;
    mapping(address => bool) public whiteListContract;

    struct LiquidateData {
        uint256 actualCollateral;
        uint256 insuranceFee;
        uint256 actualLiquidatedT0;
        uint256 actualLiquidated;
        uint256 liquidatedRemainUSDC;
    }

    constructor(
        address _jusdBank,
        address _jusdExchange,
        address _USDC,
        address _JUSD,
        address _insurance
    ) {
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    function setWhiteListContract(
        address targetContract,
        bool isValid
    ) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function JOJOFlashLoan(
        address asset,
        uint256 amount,
        address to,
        bytes calldata param
    ) external {
        //swapContract swap
        (LiquidateData memory liquidateData, bytes memory originParam) = abi
            .decode(param, (LiquidateData, bytes));
        (
            address approveTarget,
            address swapTarget,
            address liquidator,
            uint256 minReceive,
            bytes memory data
        ) = abi.decode(
                originParam,
                (address, address, address, uint256, bytes)
            );

        require(
            whiteListContract[approveTarget],
            "approve target is not in the whitelist"
        );
        require(
            whiteListContract[swapTarget],
            "swap target is not in the whitelist"
        );

        IERC20(asset).safeApprove(approveTarget, 0);
        IERC20(asset).safeApprove(approveTarget, amount);
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
        require(USDCAmount >= minReceive, "receive amount is too small");
        IERC20(USDC).approve(jusdExchange, liquidateData.actualLiquidated);
        IJUSDExchange(jusdExchange).buyJUSD(
            liquidateData.actualLiquidated,
            address(this)
        );
        IERC20(JUSD).approve(jusdBank, liquidateData.actualLiquidated);
        IJUSDBank(jusdBank).repay(liquidateData.actualLiquidated, to);

        // 2. insurance
        IERC20(USDC).safeTransfer(insurance, liquidateData.insuranceFee);
        // 3. liquidate usdc
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(USDC).safeTransfer(
                address(jusdBank),
                liquidateData.liquidatedRemainUSDC
            );
        }
        // 4. transfer to liquidator
        IERC20(USDC).safeTransfer(
            liquidator,
            USDCAmount -
                liquidateData.insuranceFee -
                liquidateData.actualLiquidated -
                liquidateData.liquidatedRemainUSDC
        );
    }
}
