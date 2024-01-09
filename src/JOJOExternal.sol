/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IDealer.sol";
import "./libraries/Errors.sol";
import "./libraries/Funding.sol";
import "./libraries/Liquidation.sol";
import "./libraries/Operation.sol";
import "./libraries/Position.sol";
import "./libraries/SignedDecimalMath.sol";
import "./libraries/Trading.sol";
import "./JOJOStorage.sol";

abstract contract JOJOExternal is JOJOStorage, IDealer {
    using SignedDecimalMath for int256;
    using SafeERC20 for IERC20;

    // ========== fund related ==========

    /// @inheritdoc IDealer
    function deposit(uint256 primaryAmount, uint256 secondaryAmount, address to) external nonReentrant {
        Funding.deposit(state, primaryAmount, secondaryAmount, to);
    }

    /// @inheritdoc IDealer
    function requestWithdraw(address from, uint256 primaryAmount, uint256 secondaryAmount) external nonReentrant {
        Funding.requestWithdraw(state, from, primaryAmount, secondaryAmount);
    }

    /// @inheritdoc IDealer
    function executeWithdraw(address from, address to, bool isInternal, bytes memory param) external nonReentrant {
        Funding.executeWithdraw(state, from, to, isInternal, param);
    }

    /// @inheritdoc IDealer
    function fastWithdraw(
        address from,
        address to,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isInternal,
        bytes memory param
    )
        external
        nonReentrant
    {
        Funding.fastWithdraw(state, from, to, primaryAmount, secondaryAmount, isInternal, param);
    }

    /// @inheritdoc IDealer
    function setOperator(address operator, bool isValid) external {
        Operation.setOperator(state, msg.sender, operator, isValid);
    }

    function approveFundOperator(address operator, uint256 primaryAmount, uint256 secondaryAmount) external {
        Operation.approveFundOperator(state, msg.sender, operator, primaryAmount, secondaryAmount);
    }

    /// @inheritdoc IDealer
    function handleBadDebt(address liquidatedTrader) external {
        Liquidation.handleBadDebt(state, liquidatedTrader);
    }

    // ========== registered perpetual only ==========

    /// @inheritdoc IDealer
    function requestLiquidation(
        address executor,
        address liquidator,
        address liquidatedTrader,
        int256 requestPaperAmount
    )
        external
        onlyRegisteredPerp
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange, int256 liqedPaperChange, int256 liqedCreditChange)
    {
        return Liquidation.requestLiquidation(
            state, msg.sender, executor, liquidator, liquidatedTrader, requestPaperAmount
        );
    }

    /// @inheritdoc IDealer
    function openPosition(address trader) external onlyRegisteredPerp {
        Position._openPosition(state, trader);
    }

    /// @inheritdoc IDealer
    function realizePnl(address trader, int256 pnl) external onlyRegisteredPerp {
        Position._realizePnl(state, trader, pnl);
    }

    /// @inheritdoc IDealer
    function approveTrade(
        address orderSender,
        bytes calldata tradeData
    )
        external
        onlyRegisteredPerp
        returns (
            address[] memory, // traderList
            int256[] memory, // paperChangeList
            int256[] memory // creditChangeList
        )
    {
        require(state.validOrderSender[orderSender], Errors.INVALID_ORDER_SENDER);

        /*
            parse tradeData
            Pass in all orders and their signatures that need to be matched.
            Also, pass in the amount you want to fill each order.
        */
        (Types.Order[] memory orderList, bytes[] memory signatureList, uint256[] memory matchPaperAmount) =
            abi.decode(tradeData, (Types.Order[], bytes[], uint256[]));
        bytes32[] memory orderHashList = new bytes32[](orderList.length);

        // validate all orders
        for (uint256 i = 0; i < orderList.length;) {
            Types.Order memory order = orderList[i];
            bytes32 orderHash = EIP712._hashTypedDataV4(domainSeparator, Trading._structHash(order));
            orderHashList[i] = orderHash;
            // validate signature
            (address recoverSigner,) = ECDSA.tryRecover(orderHash, signatureList[i]);
            if (recoverSigner != order.signer && !state.operatorRegistry[order.signer][recoverSigner]) {
                if (Address.isContract(order.signer)) {
                    require(
                        IERC1271(order.signer).isValidSignature(orderHash, signatureList[i]) == 0x1626ba7e,
                        Errors.INVALID_ORDER_SIGNATURE
                    );
                } else {
                    revert(Errors.INVALID_ORDER_SIGNATURE);
                }
            }
            // requirements
            require(Trading._info2Expiration(order.info) >= block.timestamp, Errors.ORDER_EXPIRED);
            require(
                (order.paperAmount < 0 && order.creditAmount > 0) || (order.paperAmount > 0 && order.creditAmount < 0),
                Errors.ORDER_PRICE_NEGATIVE
            );
            require(order.perp == msg.sender, Errors.PERP_MISMATCH);
            require(i == 0 || order.signer != orderList[0].signer, Errors.ORDER_SELF_MATCH);
            state.orderFilledPaperAmount[orderHash] += matchPaperAmount[i];
            require(
                state.orderFilledPaperAmount[orderHash] <= int256(orderList[i].paperAmount).abs(),
                Errors.ORDER_FILLED_OVERFLOW
            );
            unchecked {
                ++i;
            }
        }

        Types.MatchResult memory result = Trading._matchOrders(state, orderHashList, orderList, matchPaperAmount);

        // charge fee
        state.primaryCredit[orderSender] += result.orderSenderFee;
        // if orderSender pay fees to traders, check if orderSender is safe
        if (result.orderSenderFee < 0) {
            require(Liquidation._isSolidIMSafe(state, orderSender), Errors.ORDER_SENDER_NOT_SAFE);
        }

        return (result.traderList, result.paperChangeList, result.creditChangeList);
    }
}
