/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;
import "../impl/JOJODealer.sol";
import "../intf/IPerpetual.sol";
import "../lib/Types.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IFundingRateArbitrage {
    function getIndex() external view returns (uint256);
    function getCollateral() external view returns(address);
    function getTotalEarnUSDCBalance() external view returns(uint256);
}

interface IJUSDBank {
    function isAccountSafe(address user) external view returns (bool);

    function getDepositBalance(address collateral, address from) external view returns (uint256);

    function getBorrowBalance(address from) external view returns (uint256);

    function getUserCollateralList(address from) external view returns (address[] memory);

    function getCollateralPrice(address collateral) external view returns (uint256);
}

contract HelperContract {

    JOJODealer public JojoDealer;
    IJUSDBank public jusdBank;
    IFundingRateArbitrage public fundingRateArbitrage;
    address public wstToETHPrice;

    constructor(address _JOJODealer, address _JUSDBank, address _FundingRateArbitrage) {
        JojoDealer = JOJODealer(_JOJODealer);
        jusdBank = IJUSDBank(_JUSDBank);
        fundingRateArbitrage = IFundingRateArbitrage(_FundingRateArbitrage);
    }
    struct CollateralState {
        address collateral;
        uint256 balance;
    }
    struct AccountJUSDState {
        address account;
        uint256 borrowedBalance;
        bool isSafe;
        CollateralState[] collateralState;
    }
    struct AccountPerpState {
        address perp;
        int256 paper;
        int256 credit;
        uint256 liquidatePrice;
    }
    struct AccountState {
        address accountAddress;
        int256 primaryCredit;
        uint256 secondaryCredit;
        uint256 pendingPrimaryWithdraw;
        uint256 pendingSecondaryWithdraw;
        uint256 exposure;
        int256 netValue;
        uint256 initialMargin;
        uint256 maintenanceMargin;
        bool isSafe;
        uint256 executionTimestamp;
        AccountPerpState[] accountPerpState;
    }
    struct PerpState {
        address perp;
        int256 fundingRate;
        uint256 markPrice;
        Types.RiskParams riskParams;
    }

    struct HedgingState {
        uint256 USDCWalletBalance;
        int256 USDCPerpBalance;
        uint256 wstETHWalletBalance;
        uint256 wstETHBankAmount;
        uint256 JUSDBorrowAmount;
        uint256 JUSDPerpBalance;
        int256 PositionPerpAmount;
        int256 PositionCreditAmount;
        uint256 earnUSDCRate;
        uint256 wstETHToETH;
        uint256 wstETHToUSDC;
        uint256 wstETHDecimal;
        uint256 earnUSDCTotalSupply;
    }

    function getWalletBalance(address token, address wallet) public view returns(uint256) {
        return IERC20(token).balanceOf(wallet);
    }
    function getHedgingState(address perpetual) public view returns(HedgingState memory hedgingState) {
        (
        int256 primaryCredit,
        uint256 secondaryCredit,,,
        ) = IDealer(JojoDealer).getCreditOf(address(fundingRateArbitrage));
        hedgingState.USDCPerpBalance = primaryCredit;
        hedgingState.JUSDPerpBalance = secondaryCredit;
        (address USDC,,,,,,) = JojoDealer.state();
        uint256 USDCWalletBalance = IERC20(USDC).balanceOf(address(fundingRateArbitrage));
        hedgingState.USDCWalletBalance = USDCWalletBalance;
        uint256 wstETHWalletBalance = IERC20(fundingRateArbitrage.getCollateral()).balanceOf(address(fundingRateArbitrage));
        hedgingState.wstETHWalletBalance = wstETHWalletBalance;
        uint256 wstETHBankAmount = jusdBank.getDepositBalance(fundingRateArbitrage.getCollateral(), address(fundingRateArbitrage));
        hedgingState.wstETHBankAmount = wstETHBankAmount;
        uint256 JUSDBorrowAmount = jusdBank.getBorrowBalance(address(fundingRateArbitrage));
        hedgingState.JUSDBorrowAmount = JUSDBorrowAmount;
        (int256 PositionPerpAmount, int256 PositionCreditAmount) = IPerpetual(perpetual).balanceOf(address(fundingRateArbitrage));
        hedgingState.PositionPerpAmount = PositionPerpAmount;
        hedgingState.PositionCreditAmount = PositionCreditAmount;
        uint256 index = fundingRateArbitrage.getIndex();
        hedgingState.earnUSDCRate = index;
        uint256 wstETHToUSDC = IJUSDBank(jusdBank).getCollateralPrice(fundingRateArbitrage.getCollateral());
        uint256 ETHToUSDC = IDealer(JojoDealer).getMarkPrice(perpetual);
        hedgingState.wstETHToUSDC = wstETHToUSDC;
        hedgingState.wstETHDecimal = ERC20(fundingRateArbitrage.getCollateral()).decimals();
        hedgingState.wstETHToETH = (wstETHToUSDC / ETHToUSDC) * 1e12;
        hedgingState.earnUSDCTotalSupply = fundingRateArbitrage.getTotalEarnUSDCBalance();
    }

    function getAccountsStates(
        address[] calldata accounts
    ) public view returns (AccountState[] memory accountStates) {
        accountStates = new AccountState[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            accountStates[i].accountAddress = accounts[i];
            {
                (
                int256 primaryCredit,
                uint256 secondaryCredit,
                uint256 pendingPrimaryWithdraw,
                uint256 pendingSecondaryWithdraw,
                uint256 executionTimestamp
                ) = IDealer(JojoDealer).getCreditOf(accounts[i]);
                accountStates[i].primaryCredit = primaryCredit;
                accountStates[i].secondaryCredit = secondaryCredit;
                accountStates[i]
                .pendingPrimaryWithdraw = pendingPrimaryWithdraw;
                accountStates[i]
                .pendingSecondaryWithdraw = pendingSecondaryWithdraw;
                accountStates[i].executionTimestamp = executionTimestamp;
            }
            (
            int256 netValue,
            uint256 exposure,
            uint256 initialMargin,
            uint256 maintenanceMargin
            ) = IDealer(JojoDealer).getTraderRisk(accounts[i]);
            accountStates[i].netValue = netValue;
            accountStates[i].exposure = exposure;
            accountStates[i].initialMargin = initialMargin;
            accountStates[i].maintenanceMargin = maintenanceMargin;
            accountStates[i].isSafe = IDealer(JojoDealer).isSafe(accounts[i]);
            address[] memory perp = IDealer(JojoDealer).getPositions(
                accounts[i]
            );
            accountStates[i].accountPerpState = new AccountPerpState[](perp.length);
            for (uint256 j = 0; j < perp.length; j++) {
                (int256 paper, int256 credit) = IPerpetual(perp[j]).balanceOf(
                    accounts[i]
                );
                accountStates[i].accountPerpState[j].perp = perp[j];
                accountStates[i].accountPerpState[j].paper = paper;
                accountStates[i].accountPerpState[j].credit = credit;
                accountStates[i].accountPerpState[j].liquidatePrice = IDealer(
                    JojoDealer
                ).getLiquidationPrice(accounts[i], perp[j]);
            }
        }
    }
    function getPerpsStates(
        address[] calldata perps
    ) public view returns (PerpState[] memory perpStates) {
        perpStates = new PerpState[](perps.length);
        for (uint256 i = 0; i < perps.length; i++) {
            perpStates[i].perp = perps[i];
            perpStates[i].fundingRate = IDealer(JojoDealer).getFundingRate(
                perps[i]
            );
            perpStates[i].markPrice = IDealer(JojoDealer).getMarkPrice(
                perps[i]
            );
            perpStates[i].riskParams = IDealer(JojoDealer).getRiskParams(
                perps[i]
            );
        }
    }
    function getPerpPaperBalances(
        address perp,
        address[] calldata accounts
    ) public view returns (int256[] memory paperAmount) {
        paperAmount = new int256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            (int256 paper, ) = IPerpetual(perp).balanceOf(accounts[i]);
            paperAmount[i] = paper;
        }
    }
    function getAccountJUSDStates(
        address[] calldata accounts
    ) public view returns (AccountJUSDState[] memory accountJUSDState) {
        accountJUSDState = new AccountJUSDState[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            accountJUSDState[i].account = accounts[i];
            accountJUSDState[i].borrowedBalance = jusdBank.getBorrowBalance(
                accounts[i]
            );
            accountJUSDState[i].isSafe = jusdBank.isAccountSafe(accounts[i]);
            address[] memory collaterals = jusdBank.getUserCollateralList(
                accounts[i]
            );
            accountJUSDState[i].collateralState = new CollateralState[](collaterals.length);
            for (uint256 j = 0; j < collaterals.length; j++) {
                accountJUSDState[i].collateralState[j].collateral = collaterals[
                j
                ];
                accountJUSDState[i].collateralState[j].balance = jusdBank
                .getDepositBalance(collaterals[j], accounts[i]);
            }
        }
    }
}
