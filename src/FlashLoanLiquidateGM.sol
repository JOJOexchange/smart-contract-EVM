/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IJUSDBank.sol";
import "./libraries/SignedDecimalMath.sol";

contract FlashLoanLiquidateGM is Ownable {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

    address public immutable USDC;
    address public immutable JUSD;
    address public jusdBank;
    address public insurance;

    mapping(address => bool) public whiteListAsset;

    struct LiquidateData {
        uint256 actualCollateral;
        uint256 insuranceFee;
        uint256 actualLiquidatedT0;
        uint256 actualLiquidated;
        uint256 liquidatedRemainUSDC;
    }

    constructor(address _jusdBank, address _USDC, address _JUSD, address _insurance) {
        jusdBank = _jusdBank;
        USDC = _USDC;
        JUSD = _JUSD;
        insurance = _insurance;
    }

    modifier onlyBank() {
        require(jusdBank == msg.sender, "Ownable: caller only can be JUSDBank");
        _;
    }

    function setWhiteListAsset(address token, bool isValid) public onlyOwner {
        whiteListAsset[token] = isValid;
    }

    function JOJOFlashLoan(address asset, uint256, address to, bytes calldata param) external onlyBank {
        (LiquidateData memory liquidateData, bytes memory liquidatorParam) = abi.decode(param, (LiquidateData, bytes));
        address liquidator;
        assembly {
            liquidator := mload(add(liquidatorParam, 20))
        }
        require(whiteListAsset[asset], "asset is not in the whitelist");
        IERC20(asset).safeTransfer(liquidator, IERC20(asset).balanceOf(address(this)));
        IERC20(JUSD).safeTransferFrom(liquidator, address(this), liquidateData.actualLiquidated);
        IERC20(JUSD).approve(jusdBank, liquidateData.actualLiquidated);
        IJUSDBank(jusdBank).repay(liquidateData.actualLiquidated, to);

        IERC20(USDC).safeTransferFrom(
            liquidator, address(this), liquidateData.insuranceFee + liquidateData.liquidatedRemainUSDC
        );
        IERC20(USDC).safeTransfer(insurance, liquidateData.insuranceFee);
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(USDC).safeTransfer(address(jusdBank), liquidateData.liquidatedRemainUSDC);
        }
    }

    function getMultiCall(
        address withdrawalVault,
        address gmToken,
        address receiver,
        uint256 executionFee,
        uint256 gmTokenAmount,
        uint256[] memory minimumRecive
    )
        public
        pure
        returns (bytes memory)
    {
        bytes[] memory param = new bytes[](3);
        param[0] = abi.encodeWithSignature("sendWnt(address,uint256)", withdrawalVault, executionFee);
        param[1] = abi.encodeWithSignature(
            "sendTokens(address,address,uint256)",
            gmToken,
            withdrawalVault,
            gmTokenAmount
        );
        param[2] = abi.encodeWithSignature(
            "createWithdrawal(address,address,address,address,address[],address[],uint256,uint256,bool,uint256,uint256)",
            receiver,
            0x0000000000000000000000000000000000000000,
            0xff00000000000000000000000000000000000001,
            gmToken,
            new address[](0),
            new address[](0),
            minimumRecive[0],
            minimumRecive[1],
            false,
            executionFee,
            0
        );
        return abi.encodeWithSignature("multicall(bytes[])", param);
    }
}
