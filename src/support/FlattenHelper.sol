/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "../degen/DegenDepositHelper.sol";
import "../JUSDBank/FlashLoanLiquidate.sol";
import "../JUSDBank/FlashLoanRepay.sol";
import "../fundingRateLimiter/FundingRateUpdateLimiter.sol";
import "../fundingRateArbitrage/FundingRateArbitrage.sol";
import "../JOJODealer.sol";
import "../degen/DegenDealer.sol";
import "../JUSDBank/JUSDBank.sol";
import "../Perpetual.sol";
import "../token/MerkleDistributorWithDeadline.sol";
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
import "./help/IMessageHandler.sol";
import "./help/IMessageTransmitter.sol";
import "./help/ITokenMinter.sol";
import "./help/ITokenMessenger.sol";

// DO NOT REMOVE
abstract contract ContractForCodeGeneration {
    function order() external view returns (Types.Order memory order) {}
}
