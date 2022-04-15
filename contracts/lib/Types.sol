/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

library Types {
    /// @notice storage of dealer
    struct State {
        // primary underlying asset, ERC20
        address primaryAsset;
        // secondary underlying asset, ERC20
        address secondaryAsset;
        // credit, gained by deposit asset
        mapping(address => int256) primaryCredit;
        mapping(address => uint256) secondaryCredit;
        // withdrawal request time lock
        uint256 withdrawTimeLock;
        // pending primary asset withdrawal amount
        mapping(address => uint256) pendingPrimaryWithdraw;
        // pending secondary asset withdrawal amount
        mapping(address => uint256) pendingSecondaryWithdraw;
        // withdrawal request executable timestamp
        mapping(address => uint256) withdrawExecutionTimestamp;
        // perpetual contract risk parameters
        mapping(address => Types.RiskParams) perpRiskParams;
        // perpetual contract register
        address[] registeredPerp;
        // all open positions of a trader
        mapping(address => address[]) openPositions;
        // To quickly search if a trader has open position:
        // trader => perpetual contract address => hasPosition
        mapping(address => mapping(address => bool)) hasPosition;
        // For offchain pnl calculation, serial number +1 whenever position cleared
        // trader => perpetual contract address => current serial Num
        mapping(address => mapping(address => uint256)) positionSerialNum;
        // filled amount of order
        mapping(bytes32 => uint256) orderFilledPaperAmount;
        // insurance account
        address insurance;
        // EIP712 domain separator
        bytes32 domainSeparator;
    }

    struct Order {
        // address of perpetual market, not the dealer
        address perp;
        /*
            Signer is the identity of trading behavior,
            whose balance will be changed.
            Normally it shoule be an EOA account and the 
            order is valid only if the signer signed it.
            If the signer is a contract, it must implement
            isValidPerpetualOperator(address) returns(bool).
            The order is valid only if one of the valid operators
            is an EOA account and signed the order.
        */
        address signer;
        /*
            Only the orderSender can match this order. If
            orderSender is 0x0, then everyone can match this order.
        */
        address orderSender;
        // positive(negative) if you want to open long(short) position
        int128 paperAmount;
        // negative(positive) if you want to open short(long) position
        int128 creditAmount;
        /*
            ╔═══════════════════╤═════════╗
            ║ info component    │ type    ║
            ╟───────────────────┼─────────╢
            ║ makerFeeRate      │ int64   ║
            ║ takerFeeRate      │ int64   ║
            ║ expiration        │ uint64  ║
            ║ nonce             │ uint64  ║
            ╚═══════════════════╧═════════╝
        */
        bytes32 info;
    }

    // EIP712 component
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(address perp,address signer,address orderSender,int128 paperAmount,int128 creditAmount,bytes32 info)"
        );

    /// @notice risk params of a perpetual market
    struct RiskParams {
        /*
            Liquidation will happens when 
            netValue/exposure < liquidationThreshold.
            The lower liquidationThreshold, the higher leverage multiplier.
            1E18 based decimal.
        */
        uint256 liquidationThreshold;
        /*
            This is the discount rate for the liquidation, which is a 1e18 based decimal.
            markPrice * (1 - liquidationPriceOff) when liquidate long position
            markPrice * (1 + liquidationPriceOff) when liquidate short position
            1E18 based decimal.
        */
        uint256 liquidationPriceOff;
        // insurance fee rate. 1E18 based decimal.
        uint256 insuranceFeeRate;
        // funding rate
        int256 fundingRate;
        // price source of mark price
        address markPriceSource;
        // perpetual market name
        string name;
        // the market is available if true
        bool isRegistered;
    }

    /// @notice Match result obtained by parsing and validating tradeData.
    /// Contains an array of balance change.
    struct MatchResult {
        address perp;
        address[] traderList;
        int256[] paperChangeList;
        int256[] creditChangeList;
        int256 orderSenderFee;
    }
}
