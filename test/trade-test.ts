import "./utils/hooks";
import { Wallet, utils } from "ethers";
import { expect, util } from "chai";
import { basicContext, Context } from "../scripts/context";
import {
  buildOrder,
  encodeTradeData,
  getDefaultOrderEnv,
  openPosition,
  Order,
  OrderEnv,
} from "../scripts/order";
import { checkBalance, checkCredit } from "./utils/checkers";
import { revert, snapshot, timeJump } from "./utils/timemachine";
import { parseEther } from "ethers/lib/utils";

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

describe("Trade", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let trader3: Wallet;
  let orderEnv: OrderEnv;
  let baseOrder: { order: Order; hash: string; signature: string };

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    trader3 = context.traderList[2];
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader1.address
      );
    await context.dealer
      .connect(trader2)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader2.address
      );
    await context.dealer
      .connect(trader3)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader3.address
      );
    orderEnv = await getDefaultOrderEnv(context.dealer);
    baseOrder = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("1").toString(),
      utils.parseEther("-30000").toString(),
      context.traderList[0]
    );
  });

  describe("match single order", async () => {
    it("taker long", async () => {
      await openPosition(
        trader1,
        trader2,
        "1",
        "30000",
        context.perpList[0],
        orderEnv
      );

      await checkBalance(context.perpList[0], trader1.address, "1", "-30015");
      await checkBalance(context.perpList[0], trader2.address, "-1", "29997");
      await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
      await checkCredit(context, context.ownerAddress, "18", "0");
    });

    it("taker short & close position", async () => {
      await openPosition(
        trader1,
        trader2,
        "-1",
        "30000",
        context.perpList[0],
        orderEnv
      );

      await checkBalance(context.perpList[0], trader1.address, "-1", "29985");
      await checkBalance(context.perpList[0], trader2.address, "1", "-30003");
      await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
      await checkCredit(context, context.ownerAddress, "18", "0");

      await openPosition(
        trader2,
        trader1,
        "-1",
        "30000",
        context.perpList[0],
        orderEnv
      );

      await checkBalance(context.perpList[0], trader1.address, "0", "0");
      await checkBalance(context.perpList[0], trader2.address, "0", "0");
      await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
      await checkCredit(context, context.ownerAddress, "36", "0");
      await checkCredit(context, trader1.address, "-18", "1000000");
      await checkCredit(context, trader2.address, "-18", "1000000");
    });
  });

  describe("match multi orders", async () => {
    it("maker de-duplicate", async () => {
      // o1 short at price 30000 - taker
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-3").toString(),
        utils.parseEther("90000").toString(),
        context.traderList[0]
      );
      // o2 long at price 40000 - maker
      const o2 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-40000").toString(),
        context.traderList[1]
      );
      // o3 long at price 50000 - maker
      orderEnv.makerFeeRate = utils.parseEther("0.0002").toString();
      const o3 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-60000").toString(),
        context.traderList[1]
      );

      const data = encodeTradeData(
        [o1.order, o2.order, o3.order],
        [o1.signature, o2.signature, o3.signature],
        [
          utils.parseEther("2").toString(),
          utils.parseEther("1").toString(),
          utils.parseEther("1").toString(),
        ]
      );

      // should only emit one event for maker
      await expect(context.perpList[0].trade(data))
        .to.emit(context.perpList[0], "BalanceChange")
        .withArgs(
          trader2.address,
          utils.parseEther("2"),
          utils.parseEther("-100016")
        );

      const o1Filled = await context.dealer.getOrderFilledAmount(o1.hash);
      expect(o1Filled).to.be.equal(utils.parseEther("2"));

      await checkBalance(context.perpList[0], trader1.address, "-2", "99950");
      await checkBalance(context.perpList[0], trader2.address, "2", "-100016");
      await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
      await checkCredit(context, context.ownerAddress, "66", "0");
    });

    it("without maker de-duplicate", async () => {
      // o1 short at price 30000 - taker
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-3").toString(),
        utils.parseEther("90000").toString(),
        context.traderList[0]
      );
      // o2 long at price 40000 - maker
      const o2 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-40000").toString(),
        context.traderList[1]
      );
      // o3 long at price 50000 - maker
      orderEnv.makerFeeRate = utils.parseEther("-0.0002").toString();
      const o3 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("2").toString(),
        utils.parseEther("-100000").toString(),
        context.traderList[2]
      );

      const wrongData = encodeTradeData(
        [o1.order, o3.order, o2.order],
        [o1.signature, o3.signature, o2.signature],
        [
          utils.parseEther("3").toString(),
          utils.parseEther("2").toString(),
          utils.parseEther("1").toString(),
        ]
      );

      await expect(context.perpList[0].trade(wrongData)).to.be.revertedWith(
        "JOJO_ORDER_WRONG_SORTING"
      );

      const data = encodeTradeData(
        [o1.order, o2.order, o3.order],
        [o1.signature, o2.signature, o3.signature],
        [
          utils.parseEther("3").toString(),
          utils.parseEther("1").toString(),
          utils.parseEther("2").toString(),
        ]
      );

      // should only emit one event for maker
      await expect(context.perpList[0].trade(data))
        .to.emit(context.perpList[0], "BalanceChange")
        .withArgs(
          trader3.address,
          utils.parseEther("2"),
          utils.parseEther("-99980")
        );

      await checkBalance(context.perpList[0], trader1.address, "-3", "139930");
      await checkBalance(context.perpList[0], trader2.address, "1", "-40004");
      await checkBalance(context.perpList[0], trader3.address, "2", "-99980");
      await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
      await checkCredit(context, context.ownerAddress, "54", "0");
    });
  });

  describe("liquidation check in approveTrade", async () => {
    it("trade success", async () => {
      // 1000 BTC 30000000*0.03 = 900000
      // 1000 ETH 2000000*0.05 = 100000
      // taker fee: 16000
      // BTC fee 30000000 * 0.0005 = 15000
      // ETH fee 2000000 * 0.0005 = 1000
      // maker fee: 3200
      // BTC fee 30000000 * 0.0001 = 3000
      // ETH fee 2000000 * 0.0001 = 200
      await context.dealer
        .connect(trader1)
        .deposit(
          utils.parseEther("16000"),
          utils.parseEther("0"),
          trader1.address
        );
      await context.dealer
        .connect(trader2)
        .deposit(
          utils.parseEther("3200"),
          utils.parseEther("0"),
          trader2.address
        );
      await openPosition(
        trader1,
        trader2,
        "1000",
        "30000",
        context.perpList[0],
        orderEnv
      );
      await openPosition(
        trader1,
        trader2,
        "1000",
        "2000",
        context.perpList[1],
        orderEnv
      );
      let trader1Risk = await context.dealer.getTraderRisk(trader1.address);
      let trader2Risk = await context.dealer.getTraderRisk(trader2.address);
      expect(trader1Risk.netValue).to.be.equal(parseEther("1000000"));
      expect(trader1Risk.maintenanceMargin).to.be.equal(parseEther("1000000"));
      expect(trader2Risk.netValue).to.be.equal(parseEther("1000000"));
      expect(trader2Risk.maintenanceMargin).to.be.equal(parseEther("1000000"));
    });
    it("trade failed", async () => {
      await context.dealer
        .connect(trader1)
        .deposit(
          utils.parseEther("15990"),
          utils.parseEther("0"),
          trader1.address
        );
      await context.dealer
        .connect(trader2)
        .deposit(
          utils.parseEther("3199"),
          utils.parseEther("0"),
          trader2.address
        );
      await openPosition(
        trader1,
        trader2,
        "1000",
        "30000",
        context.perpList[0],
        orderEnv
      );
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[1].address,
        utils.parseEther("1000").toString(),
        utils.parseEther("-2000000").toString(),
        trader1
      );
      const o2 = await buildOrder(
        orderEnv,
        context.perpList[1].address,
        utils.parseEther("-1000").toString(),
        utils.parseEther("2000000").toString(),
        trader2
      );
      const data = encodeTradeData(
        [o1.order, o2.order],
        [o1.signature, o2.signature],
        [
          utils.parseEther("1000").toString(),
          utils.parseEther("1000").toString(),
        ]
      );
      await expect(context.perpList[1].trade(data)).to.be.revertedWith(
        "TRADER_NOT_SAFE"
      );
    });
  });

  describe("other revert cases", async () => {
    it("self match", async () => {
      // o1 short at price 30000 - taker
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-3").toString(),
        utils.parseEther("90000").toString(),
        context.traderList[0]
      );
      // o2 long at price 40000 - maker
      const o2 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-40000").toString(),
        context.traderList[0]
      );
      const data = encodeTradeData(
        [o1.order, o2.order],
        [o1.signature, o2.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data)).to.be.revertedWith(
        "JOJO_ORDER_SELF_MATCH"
      );
    });

    it("at least two traders", async () => {
      // o1 short at price 30000 - taker
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-3").toString(),
        utils.parseEther("90000").toString(),
        context.traderList[0]
      );
      const data = encodeTradeData(
        [o1.order],
        [o1.signature],
        [utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data)).to.be.revertedWith(
        "JOJO_AT_LEAST_TWO_TRADERS"
      );
    });

    it("revert cases", async () => {
      const o1 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[1]
      );
      let o2 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("0").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[1]
      );
      let o3 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("0").toString(),
        context.traderList[1]
      );

      // 1. price negative or 0
      let data1 = encodeTradeData(
        [baseOrder.order, o1.order],
        [baseOrder.signature, o1.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      let data2 = encodeTradeData(
        [baseOrder.order, o2.order],
        [baseOrder.signature, o2.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      let data3 = encodeTradeData(
        [baseOrder.order, o3.order],
        [baseOrder.signature, o3.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data1)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NEGATIVE"
      );
      await expect(context.perpList[0].trade(data2)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NEGATIVE"
      );
      await expect(context.perpList[0].trade(data3)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NEGATIVE"
      );

      // 2. signature wrong
      const o4 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[1]
      );
      let data4 = encodeTradeData(
        [baseOrder.order, o4.order],
        [o4.signature, baseOrder.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data4)).to.be.revertedWith(
        "JOJO_INVALID_ORDER_SIGNATURE"
      );

      // 3. sender wrong
      let data5 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(
        context.perpList[0].connect(trader1).trade(data5)
      ).to.be.revertedWith("JOJO_INVALID_ORDER_SENDER");

      // 4. perp wrong
      await expect(context.perpList[1].trade(data5)).to.be.revertedWith(
        "JOJO_PERP_MISMATCH"
      );

      // 5. taker match amount wrong
      let data6 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("1").toString(), utils.parseEther("0.1").toString()]
      );
      await expect(context.perpList[0].trade(data6)).to.be.revertedWith(
        "JOJO_TAKER_TRADE_AMOUNT_WRONG"
      );

      // 6. price not match
      let o7 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("40000").toString(),
        context.traderList[1]
      );
      let o7Reverse = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-40000").toString(),
        context.traderList[1]
      );
      let baseOrderReverse = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[0]
      );
      let data7 = encodeTradeData(
        [baseOrder.order, o7.order],
        [baseOrder.signature, o7.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      let data7Reverse = encodeTradeData(
        [baseOrder.order, o7Reverse.order],
        [baseOrder.signature, o7Reverse.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data7)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );
      await expect(context.perpList[0].trade(data7Reverse)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );

      let data8 = encodeTradeData(
        [o7.order, baseOrder.order],
        [o7.signature, baseOrder.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      let data8Reverse = encodeTradeData(
        [o7.order, baseOrderReverse.order],
        [o7.signature, baseOrderReverse.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data8)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );
      await expect(context.perpList[0].trade(data8Reverse)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );

      // 7. order over filled
      let data9 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("10").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data9)).to.be.revertedWith(
        "JOJO_ORDER_FILLED_OVERFLOW"
      );

      // 8. be liquidated after trading
      let o8 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-100").toString(),
        utils.parseEther("1000000").toString(),
        trader3
      );
      let o9 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("100").toString(),
        utils.parseEther("-3000000").toString(),
        trader1
      );
      let data10 = encodeTradeData(
        [o9.order, o8.order],
        [o9.signature, o8.signature],
        [utils.parseEther("100").toString(), utils.parseEther("100").toString()]
      );
      await expect(context.perpList[0].trade(data10)).to.be.revertedWith(
        "TRADER_NOT_SAFE"
      );

      // 9. order expired
      await timeJump(1000);
      await expect(context.perpList[0].trade(data5)).to.be.revertedWith(
        "JOJO_ORDER_EXPIRED"
      );
    });

    // order sender not safe
    it("order sender not safe", async () => {
      await context.primaryAsset.mint(
        [orderEnv.orderSender],
        [utils.parseEther("1000000")]
      );
      await context.secondaryAsset.mint(
        [orderEnv.orderSender],
        [utils.parseEther("1000000")]
      );
      await context.primaryAsset.approve(
        orderEnv.dealerAddress,
        utils.parseEther("1000000")
      );
      await context.secondaryAsset.approve(
        orderEnv.dealerAddress,
        utils.parseEther("1000000")
      );
      await context.dealer.deposit(
        utils.parseEther("0"),
        utils.parseEther("500000"),
        orderEnv.orderSender
      );
      orderEnv.makerFeeRate = utils.parseEther("-0.5").toString();
      orderEnv.takerFeeRate = utils.parseEther("-0.5").toString();
      let makerO = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[0]
      );
      let takerO = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("1").toString(),
        utils.parseEther("-30000").toString(),
        context.traderList[1]
      );
      let data = encodeTradeData(
        [makerO.order, takerO.order],
        [makerO.signature, takerO.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      await expect(context.perpList[0].trade(data)).to.be.revertedWith(
        "JOJO_ORDER_SENDER_NOT_SAFE"
      );
      await context.dealer.deposit(
        utils.parseEther("500000"),
        utils.parseEther("0"),
        orderEnv.orderSender
      );
      await context.perpList[0].trade(data);
      await checkCredit(context, orderEnv.orderSender, "470000", "500000");
    });
  });
});
