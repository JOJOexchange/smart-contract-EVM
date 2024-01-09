/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

library Types {
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public constant ONE = 1e18;

    /// @notice data structure of dealer
    struct State {
        // primary asset, ERC20
        address primaryAsset;
        // secondary asset, ERC20
        address secondaryAsset;
        // credit, gained by deposit assets
        mapping(address => int256) primaryCredit;
        mapping(address => uint256) secondaryCredit;
        // allow fund operators to withdraw
        mapping(address => mapping(address => uint256)) primaryCreditAllowed;
        mapping(address => mapping(address => uint256)) secondaryCreditAllowed;
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
        // perpetual contract registry, for view
        address[] registeredPerp;
        // all open positions of a trader
        mapping(address => address[]) openPositions;
        // For offchain pnl calculation, serial number +1 whenever
        // position is fully closed.
        // trader => perpetual contract address => current serial Num
        mapping(address => mapping(address => uint256)) positionSerialNum;
        // filled amount of orders
        mapping(bytes32 => uint256) orderFilledPaperAmount;
        // valid order sender registry
        mapping(address => bool) validOrderSender;
        // addresses that can make fast withdrawal
        mapping(address => bool) fastWithdrawalWhitelist;
        bool fastWithdrawDisabled;
        // operator registry
        // client => operator => isValid
        mapping(address => mapping(address => bool)) operatorRegistry;
        // insurance account
        address insurance;
        // funding rate keeper, normally an EOA account
        address fundingRateKeeper;
        uint256 maxPositionAmount;
    }

    struct Order {
        // address of perpetual market
        address perp;
        /*
            Signer is trader, the identity of  behavior,
            whose balance will be changed.
            Normally it should be an EOA account and the 
            order is valid only if the signer signed it.
            If the signer is a smart contract, it has two ways
            to sign the order. The first way is to authorize 
            another EOA address to sign for it through setOperator.
            The other way is to implement IERC1271 for self-verification.
        */
        address signer;
        // positive(negative) if you want to open long(short) position
        int128 paperAmount;
        // negative(positive) if you want to open long(short) position
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
        keccak256("Order(address perp,address signer,int128 paperAmount,int128 creditAmount,bytes32 info)");

    /// @notice risk params of a perpetual market
    struct RiskParams {
        /*
            When users withdraw funds, their margin must be equal or
            greater than the exposure * initialMarginRatio.
        */
        uint256 initialMarginRatio;
        /*
            Liquidation will happen when
            netValue < exposure * liquidationThreshold
            The lower liquidationThreshold, the higher leverage.
            This value is also known as "maintenance margin ratio".
            1E18 based decimal.
        */
        uint256 liquidationThreshold;
        /*
            The discount rate for the liquidation.
            markPrice * (1 - liquidationPriceOff) when liquidate long position
            markPrice * (1 + liquidationPriceOff) when liquidate short position
            1e18 based decimal.
        */
        uint256 liquidationPriceOff;
        // The insurance fee rate charged from liquidation.
        // 1E18 based decimal.
        uint256 insuranceFeeRate;
        // price source of mark price
        address markPriceSource;
        // perpetual market name
        string name;
        // if the market is activited
        bool isRegistered;
    }

    /// @notice Match result obtained by parsing and validating tradeData.
    /// Contains arrays of balance change.
    struct MatchResult {
        address[] traderList;
        int256[] paperChangeList;
        int256[] creditChangeList;
        int256 orderSenderFee;
    }

    struct ReserveInfo {
        // the initial mortgage rate of collateral
        // 1e18 based decimal
        uint256 initialMortgageRate;
        // max total deposit collateral amount
        uint256 maxTotalDepositAmount;
        // max deposit collateral amount per account
        uint256 maxDepositAmountPerAccount;
        // the collateral max deposit value, protect from oracle
        uint256 maxColBorrowPerAccount;
        // oracle address
        address oracle;
        // total deposit amount
        uint256 totalDepositAmount;
        // liquidation mortgage rate
        // 1e18 based decimal
        uint256 liquidationMortgageRate;
        /*
            The discount rate for the liquidation.
            price * (1 - liquidationPriceOff)
            1e18 based decimal.
        */
        uint256 liquidationPriceOff;
        // insurance fee rate
        // 1e18
        uint256 insuranceFeeRate;
        /*       
            if the mortgage collateral delisted.
            if isFinalLiquidation = true which means user can not deposit collateral and borrow USDO
        */
        bool isFinalLiquidation;
        // if allow user deposit collateral
        bool isDepositAllowed;
        // if allow user borrow USDO
        bool isBorrowAllowed;
    }

    /// @notice user param
    struct UserInfo {
        // deposit collateral ==> deposit amount
        mapping(address => uint256) depositBalance;
        mapping(address => bool) hasCollateral;
        // t0 borrow USDO amount
        uint256 t0BorrowBalance;
        // user deposit collateral list
        address[] collateralList;
    }

    struct LiquidateData {
        uint256 actualCollateral;
        uint256 insuranceFee;
        uint256 actualLiquidatedT0;
        uint256 actualLiquidated;
        uint256 liquidatedRemainUSDC;
    }
}
