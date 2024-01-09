/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/interfaces/IJUSDBank.sol";
import "../../src/interfaces/IJUSDExchange.sol";
import "../../src/interfaces/IFlashLoanReceive.sol";
import "../../src/interfaces/internal/IPriceSource.sol";
import "../../src/libraries/SignedDecimalMath.sol";

contract LiquidateCollateralRepayNotEnough is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

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

    constructor(address _jusdBank, address _jusdExchange, address _USDC, address _JUSD, address _insurance) {
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    function setWhiteListContract(address targetContract, bool isValid) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function JOJOFlashLoan(address asset, uint256 amount, address to, bytes calldata param) external {
        //swapContract swap
        (LiquidateData memory liquidateData, bytes memory originParam) = abi.decode(param, (LiquidateData, bytes));
        (address approveTarget, address swapTarget,, bytes memory data) =
            abi.decode(originParam, (address, address, address, bytes));

        require(whiteListContract[approveTarget], "approve target is not in the whitelist");
        require(whiteListContract[swapTarget], "swap target is not in the whitelist");

        IERC20(asset).approve(approveTarget, amount);
        (bool success,) = swapTarget.call(data);
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        IERC20(USDC).approve(jusdExchange, liquidateData.actualLiquidated - 1);
        IJUSDExchange(jusdExchange).buyJUSD(liquidateData.actualLiquidated - 1, address(this));
        IERC20(JUSD).approve(jusdBank, liquidateData.actualLiquidated - 1);
        IJUSDBank(jusdBank).repay(liquidateData.actualLiquidated - 1, to);
    }
}

contract LiquidateCollateralInsuranceNotEnough is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

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

    constructor(address _jusdBank, address _jusdExchange, address _USDC, address _JUSD, address _insurance) {
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    function setWhiteListContract(address targetContract, bool isValid) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function JOJOFlashLoan(address asset, uint256 amount, address to, bytes calldata param) external {
        //swapContract swap
        (LiquidateData memory liquidateData, bytes memory originParam) = abi.decode(param, (LiquidateData, bytes));
        (address approveTarget, address swapTarget,, bytes memory data) =
            abi.decode(originParam, (address, address, address, bytes));

        require(whiteListContract[approveTarget], "approve target is not in the whitelist");
        require(whiteListContract[swapTarget], "swap target is not in the whitelist");

        IERC20(asset).approve(approveTarget, amount);
        (bool success,) = swapTarget.call(data);
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        IERC20(USDC).approve(jusdExchange, liquidateData.actualLiquidated);
        IJUSDExchange(jusdExchange).buyJUSD(liquidateData.actualLiquidated, address(this));
        IERC20(JUSD).approve(jusdBank, liquidateData.actualLiquidated);
        IJUSDBank(jusdBank).repay(liquidateData.actualLiquidated, to);

        // 2. insurance
        IERC20(USDC).transfer(insurance, liquidateData.insuranceFee - 1);

        // 3. liquidate usdc
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(USDC).transfer(to, liquidateData.liquidatedRemainUSDC - 1);
        }
    }
}

contract LiquidateCollateralLiquidatedNotEnough is Ownable {
    // add this to be excluded from coverage report
    function test() public { }

    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

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

    constructor(address _jusdBank, address _jusdExchange, address _USDC, address _JUSD, address _insurance) {
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    function setWhiteListContract(address targetContract, bool isValid) public onlyOwner {
        whiteListContract[targetContract] = isValid;
    }

    function JOJOFlashLoan(address asset, uint256 amount, address to, bytes calldata param) external {
        //swapContract swap
        (LiquidateData memory liquidateData, bytes memory originParam) = abi.decode(param, (LiquidateData, bytes));
        (address approveTarget, address swapTarget,, bytes memory data) =
            abi.decode(originParam, (address, address, address, bytes));

        require(whiteListContract[approveTarget], "approve target is not in the whitelist");
        require(whiteListContract[swapTarget], "swap target is not in the whitelist");

        IERC20(asset).approve(approveTarget, amount);
        (bool success,) = swapTarget.call(data);
        if (success == false) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        IERC20(USDC).approve(jusdExchange, liquidateData.actualLiquidated);
        IJUSDExchange(jusdExchange).buyJUSD(liquidateData.actualLiquidated, address(this));
        IERC20(JUSD).approve(jusdBank, liquidateData.actualLiquidated);
        IJUSDBank(jusdBank).repay(liquidateData.actualLiquidated, to);

        // 2. insurance
        IERC20(USDC).transfer(insurance, liquidateData.insuranceFee);

        // 3. liquidate usdc
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(USDC).transfer(to, liquidateData.liquidatedRemainUSDC - 1);
        }
    }
}
