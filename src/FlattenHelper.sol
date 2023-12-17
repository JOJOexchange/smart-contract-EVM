/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "./FlashLoanLiquidate.sol";
import "./FlashLoanRepay.sol";
import "./FundingRateUpdateLimiter.sol";
import "./FundingRateArbitrage.sol";
import "./JOJODealer.sol";
import "./JUSDBank.sol";
import "./Perpetual.sol";
import "./oracleAdaptor/EmergencyOracle.sol";
import "./oracleAdaptor/OracleAdaptor.sol";
import "./subaccount/SubaccountFactory.sol";
import "./subaccount/BotSubaccountFactory.sol";
import "./subaccount/DegenSubaccountFactory.sol";
import "./support/HelperContract.sol";
import "./support/TestMarkPriceSource.sol";
import "./support/MockSwap.sol";
import "./support/TestVolatilePriceSource.sol";

// should we move this file out of test folder?
import "../test/mock/TestERC20.sol";

// DO NOT REMOVE
abstract contract ContractForCodeGeneration {
    function order() external view returns (Types.Order memory order) {}
}
