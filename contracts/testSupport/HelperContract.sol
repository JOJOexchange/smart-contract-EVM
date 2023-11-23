/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/
pragma solidity 0.8.9;
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../lib/Types.sol";
interface IJUSDBank {
    function isAccountSafe(address user) external view returns (bool);
    function getBorrowBalance(address from) external view returns (uint256);
    function getUserCollateralList(
        address from
    ) external view returns (address[] memory);
    function getDepositBalance(
        address collateral,
        address from
    ) external view returns (uint256);
}
contract HelperContract {
    IDealer public JOJODealer;
    IJUSDBank public JUSDBank;
    constructor(address _JOJODealer, address _JUSDBank) {
        JOJODealer = IDealer(_JOJODealer);
        JUSDBank = IJUSDBank(_JUSDBank);
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
                ) = IDealer(JOJODealer).getCreditOf(accounts[i]);
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
            ,
            uint256 maintenanceMargin
            ) = IDealer(JOJODealer).getTraderRisk(accounts[i]);
            accountStates[i].netValue = netValue;
            accountStates[i].exposure = exposure;
            accountStates[i].maintenanceMargin = maintenanceMargin;
            accountStates[i].isSafe = IDealer(JOJODealer).isSafe(accounts[i]);
            address[] memory perp = IDealer(JOJODealer).getPositions(
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
                    JOJODealer
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
            perpStates[i].fundingRate = IDealer(JOJODealer).getFundingRate(
                perps[i]
            );
            perpStates[i].markPrice = IDealer(JOJODealer).getMarkPrice(
                perps[i]
            );
            perpStates[i].riskParams = IDealer(JOJODealer).getRiskParams(
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
            accountJUSDState[i].borrowedBalance = JUSDBank.getBorrowBalance(
                accounts[i]
            );
            accountJUSDState[i].isSafe = JUSDBank.isAccountSafe(accounts[i]);
            address[] memory collaterals = JUSDBank.getUserCollateralList(
                accounts[i]
            );
            accountJUSDState[i].collateralState = new CollateralState[](collaterals.length);
            for (uint256 j = 0; j < collaterals.length; j++) {
                accountJUSDState[i].collateralState[j].collateral = collaterals[
                j
                ];
                accountJUSDState[i].collateralState[j].balance = JUSDBank
                .getDepositBalance(collaterals[j], accounts[i]);
            }
        }
    }
}
