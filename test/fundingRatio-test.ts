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
import { checkBalance, checkCredit } from "./checkers";

/*
  Test cases list
  - work when ratio = 0
  - work when ratio > 0
  - work when ratio < 0
  - ratio increase
  - ratio decrease
*/

describe("Trade", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let orderEnv: OrderEnv;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    await context.dealer.setVirtualCredit(
      trader1.address,
      utils.parseEther("1000000")
    );
    await context.dealer.setVirtualCredit(
      trader2.address,
      utils.parseEther("1000000")
    );
    orderEnv = await getDefaultOrderEnv(context.dealer);
  });

  it("ratio=0", async () => {
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("0")]
    );
    expect(
      await context.dealer.getFundingRatio(context.perpList[0].address)
    ).to.equal(utils.parseEther("0"));
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
  });

  it("ratio>0", async () => {
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("1")]
    );
    expect(
        await context.dealer.getFundingRatio(context.perpList[0].address)
      ).to.equal(utils.parseEther("1"));
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
  });

  it("ratio<0", async () => {
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("-1")]
    );
    expect(
        await context.dealer.getFundingRatio(context.perpList[0].address)
      ).to.equal(utils.parseEther("-1"));
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
  });

  it("ratio increase", async () => {
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("-1")]
    );
    await openPosition(
      trader1,
      trader2,
      "1",
      "30000",
      context.perpList[0],
      orderEnv
    );
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("-0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30014.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29996.5");
    await context.dealer.updateFundingRatio(
      [context.perpList[0].address],
      [utils.parseEther("0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30013.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29995.5");
  });

  it("ratio decrease", async () => {
    await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("1")]
      );
      await openPosition(
        trader1,
        trader2,
        "1",
        "30000",
        context.perpList[0],
        orderEnv
      );
      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("0.5")]
      );
      await checkBalance(context.perpList[0], trader1.address, "1", "-30015.5");
      await checkBalance(context.perpList[0], trader2.address, "-1", "29997.5");
      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("-0.5")]
      );
      await checkBalance(context.perpList[0], trader1.address, "1", "-30016.5");
      await checkBalance(context.perpList[0], trader2.address, "-1", "29998.5");
  });
});
