/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../FlashLoanLiquidate.sol";
import "../FlashLoanRepay.sol";
import "../FundingRateUpdateLimiter.sol";
import "../FundingRateArbitrage.sol";
import "../JOJODealer.sol";
import "../JUSDBank.sol";
import "../Perpetual.sol";
import "../oracle/EmergencyOracle.sol";
import "../oracle/OracleAdaptor.sol";
import "../subaccount/SubaccountFactory.sol";
import "../subaccount/BotSubaccountFactory.sol";
import "../subaccount/DegenSubaccountFactory.sol";
import "../support/HelperContract.sol";
import "../support/TestMarkPriceSource.sol";
import "../support/MockSwap.sol";
import "../support/TestVolatilePriceSource.sol";
import "./TestERC20.sol";

// DO NOT REMOVE
abstract contract ContractForCodeGeneration {
    function order() external view returns (Types.Order memory order) { }
}
