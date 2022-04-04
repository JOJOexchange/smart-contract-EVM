import "./utils/hooks"
import { Wallet, utils } from "ethers";
import { expect } from "chai";
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
  - change funding ratio
  - self match

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
    await context.dealer.setVirtualCredit(
      trader1.address,
      utils.parseEther("1000000")
    );
    await context.dealer.setVirtualCredit(
      trader2.address,
      utils.parseEther("1000000")
    );
    await context.dealer.setVirtualCredit(
      trader3.address,
      utils.parseEther("1000000")
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
      await expect(context.perpList[0].trade(data))
        .to.emit(context.perpList[0], "BalanceChange")
        .withArgs(
          trader1.address,
          utils.parseEther("1"),
          utils.parseEther("-40004")
        );

      await checkBalance(context.perpList[0], trader1.address, "0", "0");
      await checkCredit(context, trader1.address, "-24", "1000000");
      await checkCredit(context, context.ownerAddress, "24", "0");
    });
  });

  describe("revert cases", async () => {
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
      expect(context.perpList[0].trade(data1)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NEGATIVE"
      );
      expect(context.perpList[0].trade(data2)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NEGATIVE"
      );
      expect(context.perpList[0].trade(data3)).to.be.revertedWith(
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
      expect(context.perpList[0].trade(data4)).to.be.revertedWith(
        "JOJO_INVALID_ORDER_SIGNATURE"
      );

      // 3. sender wrong
      let data5 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      expect(
        context.perpList[0].connect(trader1).trade(data5)
      ).to.be.revertedWith("JOJO_INVALID_ORDER_SENDER");

      // 4. perp wrong
      expect(context.perpList[1].trade(data5)).to.be.revertedWith(
        "JOJO_PERP_MISMATCH"
      );

      // 5. taker match amount wrong
      let data6 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("1").toString(), utils.parseEther("0.1").toString()]
      );
      expect(context.perpList[0].trade(data6)).to.be.revertedWith(
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
      let data7 = encodeTradeData(
        [baseOrder.order, o7.order],
        [baseOrder.signature, o7.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      expect(context.perpList[0].trade(data7)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );

      let data8 = encodeTradeData(
        [o7.order, baseOrder.order],
        [o7.signature, baseOrder.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      expect(context.perpList[0].trade(data8)).to.be.revertedWith(
        "JOJO_ORDER_PRICE_NOT_MATCH"
      );

      // 7. order over filled
      let data9 = encodeTradeData(
        [baseOrder.order, o4.order],
        [baseOrder.signature, o4.signature],
        [utils.parseEther("10").toString(), utils.parseEther("1").toString()]
      );
      expect(context.perpList[0].trade(data9)).to.be.revertedWith(
        "JOJO_ORDER_FILLED_OVERFLOW"
      );

      // 8. be liquidated after trading
      let o8 = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[2]
      );
      await context.dealer.setVirtualCredit(
        trader3.address,
        utils.parseEther("10")
      );
      let data10 = encodeTradeData(
        [baseOrder.order, o8.order],
        [baseOrder.signature, o8.signature],
        [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
      );
      expect(context.perpList[0].trade(data10)).to.be.revertedWith(
        "TRADER_NOT_SAFE"
      );

      // 9. order expired
      await timeJump(1000)
      expect( context.perpList[0].trade(data5)
      ).to.be.revertedWith("JOJO_ORDER_EXPIRED");
    });

    // order sender not safe
    it("order sender not safe",async () => {
      orderEnv.makerFeeRate = utils.parseEther("-0.5").toString()
      orderEnv.takerFeeRate = utils.parseEther("-0.5").toString()
      let makerO = await buildOrder(
        orderEnv,
        context.perpList[0].address,
        utils.parseEther("-1").toString(),
        utils.parseEther("30000").toString(),
        context.traderList[0]
      );
      let takerO= await buildOrder(
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
      expect(context.perpList[0].trade(data)).to.be.revertedWith(
        "JOJO_ORDER_SENDER_NOT_SAFE"
      );
    })
  });
});
