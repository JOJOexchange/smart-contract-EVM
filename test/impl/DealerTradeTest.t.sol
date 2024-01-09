/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";
import "../mocks/MockERC1271.sol";
import "../mocks/MockERC1271Failed.sol";
import "../../src/subaccount/DegenSubaccount.sol";
import "../../src/subaccount/DegenSubaccountFactory.sol";

/*
  Test cases list
  - single match 
    - taker long
    - taker short
    - close position
  - multi match
    - maker de-duplicate
    - order with different maker fee rate
    - using maker price
    - without maker de-duplicate
    - negative fee rate
  - change funding rate

  Revert cases list
  - order price negative
  - order amount 0
  - wrong signature
  - wrong sender
  - wrong perp
  - wrong match amount
  - price not match
  - order over filled
  - be liquidated
*/
// Check dealer's trade
contract TradeTest is Checkers {
    function before() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1_000_000e6, traders[0]);
        vm.stopPrank();

        vm.startPrank(traders[1]);
        jojoDealer.deposit(0, 1_000_000e6, traders[1]);
        vm.stopPrank();

        vm.startPrank(traders[2]);
        jojoDealer.deposit(0, 1_000_000e6, traders[2]);
        vm.stopPrank();
    }

    function testMatchSigleOrderTakerLong() public {
        before();
        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, 1e18);
        assertEq(trader0Credit, -30_015e6);
        assertEq(trader1Paper, -1e18);
        assertEq(trader1Credit, 29_997e6);
    }

    function testMatchSigleOrderTakerShort() public {
        before();
        trade(-1e18, 30_000e6, 1e18, -30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, -1e18);
        assertEq(trader0Credit, 29_985e6);
        assertEq(trader1Paper, 1e18);
        assertEq(trader1Credit, -30_003e6);

        trade(1e18, -30_000e6, -1e18, 30_000e6, 1e18, 1e18, address(perpList[0]));
        (int256 trader0Paper1, int256 trader0Credit1) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper1, int256 trader1Credit1) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper1, 0);
        assertEq(trader0Credit1, 0);
        assertEq(trader1Paper1, 0);
        assertEq(trader1Credit1, 0);
        checkCredit(traders[0], -30e6, 1_000_000e6);
        checkCredit(traders[1], -6e6, 1_000_000e6);
    }

    function buildOrder(
        address signer,
        uint256 privateKey,
        int128 paper,
        int128 credit,
        address perpetual,
        int64 makerFeeRate
    )
        public
        view
        returns (Types.Order memory order, bytes memory signature)
    {
        int64 takerFeeRate = 5e14;
        bytes memory infoBytes =
            abi.encodePacked(makerFeeRate, takerFeeRate, uint64(block.timestamp), uint64(block.timestamp));
        order = Types.Order({
            perp: perpetual,
            signer: signer,
            paperAmount: paper,
            creditAmount: credit,
            info: bytes32(infoBytes)
        });
        bytes32 domainSeparator = EIP712Test._buildDomainSeparator("JOJO", "1", address(jojoDealer));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, EIP712Test._structHash(order)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function constructTradeData(
        Types.Order memory order1,
        Types.Order memory order2,
        Types.Order memory order3,
        bytes memory signature1,
        bytes memory signature2,
        bytes memory signature3,
        uint256 matchPaperAmount1,
        uint256 matchPaperAmount2,
        uint256 matchPaperAmount3
    )
        internal
        pure
        returns (bytes memory)
    {
        Types.Order[] memory orderList = new Types.Order[](3);
        orderList[0] = order1;
        orderList[1] = order2;
        orderList[2] = order3;
        bytes[] memory signatureList = new bytes[](3);
        signatureList[0] = signature1;
        signatureList[1] = signature2;
        signatureList[2] = signature3;
        uint256[] memory matchPaperAmount = new uint256[](3);
        matchPaperAmount[0] = matchPaperAmount1;
        matchPaperAmount[1] = matchPaperAmount2;
        matchPaperAmount[2] = matchPaperAmount3;
        return abi.encode(orderList, signatureList, matchPaperAmount);
    }

    function testMatchMultiOrderDeDuplicate() public {
        before();
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(traders[0], tradersKey[0], -3e18, 90_000e6, address(perpList[0]), 2e14);
        (Types.Order memory order2, bytes memory signature2) =
            buildOrder(traders[1], tradersKey[1], 1e18, -40_000e6, address(perpList[0]), 2e14);
        (Types.Order memory order3, bytes memory signature3) =
            buildOrder(traders[1], tradersKey[1], 1e18, -60_000e6, address(perpList[0]), 2e14);

        bytes memory tradeData =
            constructTradeData(order1, order2, order3, signature1, signature2, signature3, 2e18, 1e18, 1e18);
        Perpetual(perpList[0]).trade(tradeData);
        (int256 trader0Paper, int256 trader0Credit) = perpList[0].balanceOf(traders[0]);
        (int256 trader1Paper, int256 trader1Credit) = perpList[0].balanceOf(traders[1]);
        assertEq(trader0Paper, -2e18);
        assertEq(trader0Credit, 99_950e6);
        assertEq(trader1Paper, 2e18);
        assertEq(trader1Credit, -100_020e6);
    }

    function testLiquidtionTradeSuccess() public {
        before();
        vm.startPrank(traders[0]);
        jojoDealer.deposit(16_000e6, 0, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(3200e6, 0, traders[1]);
        vm.stopPrank();
        trade(1000e18, -30_000_000e6, -1000e18, 30_000_000e6, 1000e18, 1000e18, address(perpList[0]));
        trade(1000e18, -2_000_000e6, -1000e18, 2_000_000e6, 1000e18, 1000e18, address(perpList[1]));

        (int256 perpNetValue0,,, uint256 maintenanceMargin0) = JOJODealer(jojoDealer).getTraderRisk(traders[0]);
        (int256 perpNetValue1,,, uint256 maintenanceMargin1) = JOJODealer(jojoDealer).getTraderRisk(traders[1]);
        assertEq(perpNetValue0, 1_000_000e6);
        assertEq(maintenanceMargin0, 1_000_000e6);
        assertEq(perpNetValue1, 1_000_000e6);
        assertEq(maintenanceMargin1, 1_000_000e6);
    }

    function testLiquidtionTradeFailed() public {
        before();
        vm.startPrank(traders[0]);
        jojoDealer.deposit(15_990e6, 0, traders[0]);
        vm.stopPrank();
        vm.startPrank(traders[1]);
        jojoDealer.deposit(3199e6, 0, traders[1]);
        vm.stopPrank();
        trade(1000e18, -30_000_000e6, -1000e18, 30_000_000e6, 1000e18, 1000e18, address(perpList[0]));
        cheats.expectRevert("TRADER_NOT_SAFE");
        trade(1000e18, -2_000_000e6, -1000e18, 2_000_000e6, 1000e18, 1000e18, address(perpList[1]));
    }

    function testTradeSelfMatch() public {
        before();
        (Types.Order memory order2, bytes memory signature2) =
            buildOrder(traders[1], tradersKey[1], 1e18, -40_000e6, address(perpList[0]), 1e14);
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(traders[1], tradersKey[1], -1e18, 40_000e6, address(perpList[0]), 1e14);
        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = order1;
        orderList[1] = order2;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = signature1;
        signatureList[1] = signature2;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = 1e18;
        matchPaperAmount[1] = 1e18;

        cheats.expectRevert("JOJO_ORDER_SELF_MATCH");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
    }

    function testTradeOneTraders() public {
        before();
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(traders[1], tradersKey[1], -1e18, 40_000e6, address(perpList[0]), 1e14);
        Types.Order[] memory orderList = new Types.Order[](1);
        orderList[0] = order1;
        bytes[] memory signatureList = new bytes[](1);
        signatureList[0] = signature1;
        uint256[] memory matchPaperAmount = new uint256[](1);
        matchPaperAmount[0] = 1e18;

        cheats.expectRevert("JOJO_AT_LEAST_TWO_TRADERS");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
    }

    function testTradeReverts() public {
        before();
        (Types.Order memory basedorder, bytes memory basedSig) =
            buildOrder(traders[0], tradersKey[0], 1e18, -30_000e6, address(perpList[0]), 1e14);
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(traders[1], tradersKey[1], 1e18, 30_000e6, address(perpList[0]), 1e14);
        (Types.Order memory order2, bytes memory signature2) =
            buildOrder(traders[1], tradersKey[1], 0, 30_000e6, address(perpList[0]), 1e14);
        (Types.Order memory order3, bytes memory signature3) =
            buildOrder(traders[1], tradersKey[1], 1e18, 0, address(perpList[0]), 1e14);
        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = basedorder;
        orderList[1] = order1;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = basedSig;
        signatureList[1] = signature1;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = 1e18;
        matchPaperAmount[1] = 1e18;

        // 1. JOJO_ORDER_PRICE_NEGATIVE
        cheats.expectRevert("JOJO_ORDER_PRICE_NEGATIVE");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        orderList[1] = order2;
        signatureList[1] = signature2;
        cheats.expectRevert("JOJO_ORDER_PRICE_NEGATIVE");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        orderList[1] = order3;
        signatureList[1] = signature3;
        cheats.expectRevert("JOJO_ORDER_PRICE_NEGATIVE");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        // 2. JOJO_INVALID_ORDER_SIGNATURE

        (Types.Order memory order4, bytes memory signature4) =
            buildOrder(traders[1], tradersKey[1], -1e18, 30_000e6, address(perpList[0]), 1e14);
        orderList[1] = order4;
        signatureList[1] = signature3;
        cheats.expectRevert("JOJO_INVALID_ORDER_SIGNATURE");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        // 3.  sender wrong
        vm.startPrank(traders[0]);
        cheats.expectRevert("JOJO_INVALID_ORDER_SENDER");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        vm.stopPrank();

        // 4.  perp wrong
        cheats.expectRevert("JOJO_PERP_MISMATCH");
        Perpetual(perpList[1]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        // 5.  order over filled
        matchPaperAmount[1] = 2e18;
        orderList[1] = order4;
        signatureList[1] = signature4;
        cheats.expectRevert("JOJO_ORDER_FILLED_OVERFLOW");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        // 6.  taker match amount wrong
        matchPaperAmount[1] = 1e17;
        orderList[1] = order4;
        signatureList[1] = signature4;
        cheats.expectRevert("JOJO_TAKER_TRADE_AMOUNT_WRONG");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        vm.warp(100_000);
        matchPaperAmount[1] = 1e18;
        cheats.expectRevert("JOJO_ORDER_EXPIRED");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        // 8. order sender NotSafe
        vm.warp(0);
        {
            (Types.Order memory order8, bytes memory signature8) =
                buildOrder(traders[1], tradersKey[1], -1e18, 30_000e6, address(perpList[0]), -8e14);
            matchPaperAmount[1] = 1e18;
            orderList[1] = order8;
            signatureList[1] = signature8;
            cheats.expectRevert("JOJO_ORDER_SENDER_NOT_SAFE");
            Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        }

        {
            // 9. invalid signature
            MockERC1271Failed mock1271Fail = new MockERC1271Failed();
            (Types.Order memory order10, bytes memory signature10) =
                buildOrder(traders[1], tradersKey[1], -1e18, 30_000e6, address(perpList[0]), 1e14);
            matchPaperAmount[1] = 1e18;
            order10.signer = address(mock1271Fail);
            orderList[1] = order10;
            signatureList[1] = signature10;
            cheats.expectRevert("JOJO_INVALID_ORDER_SIGNATURE");
            Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        }

        MockERC1271 mock1271 = new MockERC1271();
        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(jojoDealer), 10_000e6);
        jojoDealer.deposit(10_000e6, 0, address(mock1271));
        (Types.Order memory order9, bytes memory signature9) =
            buildOrder(traders[1], tradersKey[1], -1e18, 30_000e6, address(perpList[0]), 1e14);
        matchPaperAmount[1] = 1e18;
        order9.signer = address(mock1271);
        orderList[1] = order9;
        signatureList[1] = signature9;
        jojoDealer.setMaxPositionAmount(0);
        cheats.expectRevert("JOJO_POSITION_AMOUNT_REACH_UPPER_LIMIT");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        jojoDealer.setMaxPositionAmount(10);
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
    }

    function testPriceRevert() public {
        before();
        (Types.Order memory basedorder, bytes memory basedSig) =
            buildOrder(traders[0], tradersKey[0], 1e18, -30_000e6, address(perpList[0]), 1e14);
        (Types.Order memory order7, bytes memory signature7) =
            buildOrder(traders[1], tradersKey[1], -1e18, 40_000e6, address(perpList[0]), 1e14);
        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = basedorder;
        orderList[1] = order7;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = basedSig;
        signatureList[1] = signature7;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = 1e18;
        matchPaperAmount[1] = 1e18;
        cheats.expectRevert("JOJO_ORDER_PRICE_NOT_MATCH");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        (Types.Order memory order7R, bytes memory signature7R) =
            buildOrder(traders[1], tradersKey[1], 1e18, -40_000e6, address(perpList[0]), 1e14);
        orderList[1] = order7R;
        signatureList[1] = signature7R;
        cheats.expectRevert("JOJO_ORDER_PRICE_NOT_MATCH");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        orderList[0] = order7;
        orderList[1] = basedorder;
        signatureList[0] = signature7;
        signatureList[1] = basedSig;
        cheats.expectRevert("JOJO_ORDER_PRICE_NOT_MATCH");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));

        (Types.Order memory baseR, bytes memory signature7BR) =
            buildOrder(traders[0], tradersKey[0], -1e18, 30_000e6, address(perpList[0]), 1e14);
        orderList[1] = baseR;
        signatureList[1] = signature7BR;
        cheats.expectRevert("JOJO_ORDER_PRICE_NOT_MATCH");
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
    }

    function testDegenSubaccountOpenPosition() public {
        vm.startPrank(traders[0]);
        jojoDealer.deposit(0, 1000e6, traders[0]);
        vm.stopPrank();

        vm.startPrank(traders[1]);
        jojoDealer.deposit(0, 10_000e6, traders[1]);
        vm.stopPrank();

        vm.startPrank(traders[2]);
        jojoDealer.deposit(0, 1000e6, traders[2]);
        vm.stopPrank();

        DegenSubaccountFactory degenFac = new DegenSubaccountFactory(address(jojoDealer), address(this));
        (Types.Order memory basedorder, bytes memory basedSig) =
            buildOrder(traders[0], tradersKey[0], 1e18, -30_000e6, address(perpList[0]), 0);
        vm.startPrank(traders[1]);
        usdc.approve(address(jojoDealer), 1000e6);
        address degenAccount = degenFac.newSubaccount();
        jojoDealer.deposit(1000e6, 0, degenAccount);
        (Types.Order memory order, bytes memory orderSig) =
            buildOrder(degenAccount, tradersKey[1], -1e18, 30_000e6, address(perpList[0]), 0);
        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = basedorder;
        orderList[1] = order;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = basedSig;
        signatureList[1] = orderSig;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = 1e18;
        matchPaperAmount[1] = 1e18;
        vm.stopPrank();
        Perpetual(perpList[0]).trade(abi.encode(orderList, signatureList, matchPaperAmount));
        // revert for netValue less than 0
        DegenSubaccount(degenAccount).getMaxWithdrawAmount(degenAccount);
        priceSourceList[0].setMarkPrice(100_000e6);
        cheats.expectRevert("netValue is less than 0");
        DegenSubaccount(degenAccount).getMaxWithdrawAmount(degenAccount);

        // revert for netValue is less than maintenance margin
        priceSourceList[0].setMarkPrice(30_694e6);
        cheats.expectRevert("netValue is less than maintenance margin");
        DegenSubaccount(degenAccount).getMaxWithdrawAmount(degenAccount);
    }
}
