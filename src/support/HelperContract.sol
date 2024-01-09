/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IJUSDBank.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/Types.sol";
import "../FundingRateArbitrage.sol";

contract HelperContract {
    JOJODealer public jojoDealer;
    IJUSDBank public jusdBank;
    FundingRateArbitrage public fundingRateArbitrage;

    constructor(address _JOJODealer, address _JUSDBank, address _FundingRateArbitrage) {
        jojoDealer = JOJODealer(_JOJODealer);
        jusdBank = IJUSDBank(_JUSDBank);
        fundingRateArbitrage = FundingRateArbitrage(_FundingRateArbitrage);
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
        uint256 ethWalletBalance;
        uint256 ethBankAmount;
        uint256 JUSDBorrowAmount;
        uint256 JUSDPerpBalance;
        int256 PositionPerpAmount;
        int256 PositionCreditAmount;
        uint256 earnUSDCRate;
        uint256 ethToUSDC;
        uint256 ethDecimal;
        uint256 earnUSDCTotalSupply;
        int256 perpNetValue;
    }

    struct AccountHedgingState {
        uint256 earnUSDCBalance;
        uint256 jusdOutside;
    }

    function getWalletBalance(address token, address wallet) public view returns (uint256) {
        return IERC20(token).balanceOf(wallet);
    }

    function getAccountHedgingStates(address[] calldata accounts)
        public
        view
        returns (AccountHedgingState[] memory accountHedgingStates)
    {
        accountHedgingStates = new AccountHedgingState[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            accountHedgingStates[i].earnUSDCBalance = fundingRateArbitrage.earnUSDCBalance(accounts[i]);
            accountHedgingStates[i].jusdOutside = fundingRateArbitrage.jusdOutside(accounts[i]);
        }
    }

    function getWithdrawRequestList(uint256[] calldata lists)
        public
        view
        returns (FundingRateArbitrage.WithdrawalRequest[] memory withdrawalRequests)
    {
        withdrawalRequests = new FundingRateArbitrage.WithdrawalRequest[](lists.length);
        for (uint256 i = 0; i < lists.length; i++) {
            (uint256 earnUSDCAmount, address user, bool isExecuted) = fundingRateArbitrage.withdrawalRequests(lists[i]);
            withdrawalRequests[i].earnUSDCAmount = earnUSDCAmount;
            withdrawalRequests[i].user = user;
            withdrawalRequests[i].isExecuted = isExecuted;
        }
    }

    function getHedgingState(address perpetual) public view returns (HedgingState memory hedgingState) {
        (int256 primaryCredit, uint256 secondaryCredit,,,) =
            IDealer(jojoDealer).getCreditOf(address(fundingRateArbitrage));
        hedgingState.USDCPerpBalance = primaryCredit;
        hedgingState.JUSDPerpBalance = secondaryCredit;
        (address USDC,,,,,,) = jojoDealer.state();
        uint256 USDCWalletBalance = IERC20(USDC).balanceOf(address(fundingRateArbitrage));
        hedgingState.USDCWalletBalance = USDCWalletBalance;
        uint256 ethWalletBalance = IERC20(fundingRateArbitrage.collateral()).balanceOf(address(fundingRateArbitrage));
        hedgingState.ethWalletBalance = ethWalletBalance;
        uint256 ethBankAmount =
            jusdBank.getDepositBalance(fundingRateArbitrage.collateral(), address(fundingRateArbitrage));
        hedgingState.ethBankAmount = ethBankAmount;
        uint256 JUSDBorrowAmount = jusdBank.getBorrowBalance(address(fundingRateArbitrage));
        hedgingState.JUSDBorrowAmount = JUSDBorrowAmount;
        (int256 PositionPerpAmount, int256 PositionCreditAmount) =
            IPerpetual(perpetual).balanceOf(address(fundingRateArbitrage));
        hedgingState.PositionPerpAmount = PositionPerpAmount;
        hedgingState.PositionCreditAmount = PositionCreditAmount;
        uint256 index = fundingRateArbitrage.getIndex();
        hedgingState.earnUSDCRate = index;
        uint256 ethToUSDC = IJUSDBank(jusdBank).getCollateralPrice(fundingRateArbitrage.collateral());
        hedgingState.ethDecimal = ERC20(fundingRateArbitrage.collateral()).decimals();
        hedgingState.ethToUSDC = ethToUSDC;
        hedgingState.earnUSDCTotalSupply = fundingRateArbitrage.totalEarnUSDCBalance();
        (int256 perpNetValue,,,) = jojoDealer.getTraderRisk(address(fundingRateArbitrage));
        hedgingState.perpNetValue = perpNetValue;
    }

    function getAccountsStates(address[] calldata accounts) public view returns (AccountState[] memory accountStates) {
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
                ) = IDealer(jojoDealer).getCreditOf(accounts[i]);
                accountStates[i].primaryCredit = primaryCredit;
                accountStates[i].secondaryCredit = secondaryCredit;
                accountStates[i].pendingPrimaryWithdraw = pendingPrimaryWithdraw;
                accountStates[i].pendingSecondaryWithdraw = pendingSecondaryWithdraw;
                accountStates[i].executionTimestamp = executionTimestamp;
            }
            (int256 netValue, uint256 exposure, uint256 initialMargin, uint256 maintenanceMargin) =
                IDealer(jojoDealer).getTraderRisk(accounts[i]);
            accountStates[i].netValue = netValue;
            accountStates[i].exposure = exposure;
            accountStates[i].initialMargin = initialMargin;
            accountStates[i].maintenanceMargin = maintenanceMargin;
            accountStates[i].isSafe = IDealer(jojoDealer).isSafe(accounts[i]);
            address[] memory perp = IDealer(jojoDealer).getPositions(accounts[i]);
            accountStates[i].accountPerpState = new AccountPerpState[](perp.length);
            for (uint256 j = 0; j < perp.length; j++) {
                (int256 paper, int256 credit) = IPerpetual(perp[j]).balanceOf(accounts[i]);
                accountStates[i].accountPerpState[j].perp = perp[j];
                accountStates[i].accountPerpState[j].paper = paper;
                accountStates[i].accountPerpState[j].credit = credit;
                accountStates[i].accountPerpState[j].liquidatePrice =
                    IDealer(jojoDealer).getLiquidationPrice(accounts[i], perp[j]);
            }
        }
    }

    function getPerpsStates(address[] calldata perps) public view returns (PerpState[] memory perpStates) {
        perpStates = new PerpState[](perps.length);
        for (uint256 i = 0; i < perps.length; i++) {
            perpStates[i].perp = perps[i];
            perpStates[i].fundingRate = IDealer(jojoDealer).getFundingRate(perps[i]);
            perpStates[i].markPrice = IDealer(jojoDealer).getMarkPrice(perps[i]);
            perpStates[i].riskParams = IDealer(jojoDealer).getRiskParams(perps[i]);
        }
    }

    function getPerpPaperBalances(
        address perp,
        address[] calldata accounts
    )
        public
        view
        returns (int256[] memory paperAmount)
    {
        paperAmount = new int256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            (int256 paper,) = IPerpetual(perp).balanceOf(accounts[i]);
            paperAmount[i] = paper;
        }
    }

    function getAccountJUSDStates(address[] calldata accounts)
        public
        view
        returns (AccountJUSDState[] memory accountJUSDState)
    {
        accountJUSDState = new AccountJUSDState[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            accountJUSDState[i].account = accounts[i];
            accountJUSDState[i].borrowedBalance = jusdBank.getBorrowBalance(accounts[i]);
            accountJUSDState[i].isSafe = jusdBank.isAccountSafe(accounts[i]);
            address[] memory collaterals = jusdBank.getUserCollateralList(accounts[i]);
            accountJUSDState[i].collateralState = new CollateralState[](collaterals.length);
            for (uint256 j = 0; j < collaterals.length; j++) {
                accountJUSDState[i].collateralState[j].collateral = collaterals[j];
                accountJUSDState[i].collateralState[j].balance = jusdBank.getDepositBalance(collaterals[j], accounts[i]);
            }
        }
    }
}
