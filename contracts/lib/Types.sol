/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

library Types {
    struct State {
        // underlying asset
        address underlyingAsset; // IERC20
        // insurance account
        address insurance;
        // perpetual contract register
        mapping(address => Types.RiskParams) perpRiskParams;
        address[] registeredPerp;
        // credit
        mapping(address => int256) trueCredit; // created by deposit funding, can be converted to funding
        mapping(address => uint256) virtualCredit; // for market maker, can not converted to any asset, only for trading
        // account position register
        mapping(address => address[]) openPositions; // all user's open positions, for liquidation check
        mapping(address => mapping(address => bool)) hasPosition; // user => perp => hasPosition
        mapping(address => mapping(address => uint256)) positionSerialNum; // user => perp => serial Num increase whenever last position cleared
        // withdraw control
        uint256 withdrawTimeLock;
        mapping(address => uint256) pendingWithdraw;
        mapping(address => uint256) requestWithdrawTimestamp;
        // order state
        mapping(bytes32 => uint256) filledPaperAmount;
        // EIP712 domain separator
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
        uint256 nonce;
    }

    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(address perp,int256 paperAmount,int256 creditAmount,int128 makerFeeRate,int128 takerFeeRate,address signer,address orderSender,uint256 expiration,uint256 nonce)"
        );

    struct RiskParams {
        // liquidate when netValue/exposure < liquidationThreshold
        // the lower liquidationThreshold, leverage multiplier higher
        uint256 liquidationThreshold;
        uint256 liquidationPriceOff;
        // uint256 maxPositionSize; // count in paper amount
        uint256 insuranceFeeRate;
        int256 fundingRate;
        address markPriceSource;
        string name;
        bool isRegistered;
    }

    struct MatchResult {
        address perp;
        address[] traderList;
        int256[] paperChangeList;
        int256[] creditChangeList;
        int256 orderSenderFee;
    }
}