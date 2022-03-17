/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

library Types {
    struct State {
        address underlyingAsset; // IERC20
        address insurance;
        mapping(address => Types.RiskParams) perpRiskParams;
        address[] registeredPerp;
        mapping(address => int256) trueCredit; // created by deposit funding, can be converted to funding
        mapping(address => uint256) virtualCredit; // for market maker, can not converted to any asset, only for trading
        mapping(address => address[]) openPositions; // all user's open positions
        mapping(address => mapping(address => bool)) hasPosition; // user => perp => hasPosition
        uint256 withdrawTimeLock;
        mapping(address => uint256) pendingWithdraw;
        mapping(address => uint256) requestWithdrawTimestamp;
        mapping(bytes32 => uint256) filledPaperAmount;
        address orderValidator;
        bytes32 domainSeparator;
    }

    struct Order {
        address perp;
        int256 paperAmount;
        int256 creditAmount;
        int128 makerFeeRate;
        int128 takerFeeRate;
        address signer;
        address orderSender;
        uint256 expiration;
        uint256 salt;
    }

    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(address perp, int256 paperAmount, int256 creditAmount, int128 makerFeeRate, int128 takerFeeRate, address signer, address sender, uint256 expiration, uint256 salt)"
        );

    struct RiskParams {
        // liquidate when netValue/exposure < liquidationThreshold
        // the lower liquidationThreshold, leverage multiplier higher
        uint256 liquidationThreshold;
        uint256 liquidationPriceOff;
        uint256 insuranceFeeRate;
        int256 fundingRatio;
        address markPriceSource;
        string name;
        bool isRegistered;
    }

    struct MatchResult {
        address taker;
        address[] makerList;
        int256[] tradePaperAmountList;
        int256[] tradeCreditAmountList;
        int256 takerFee;
        int256[] makerFeeList;
    }
}
