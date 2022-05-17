import "./utils/hooks";
import { Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import { getDefaultOrderEnv, openPosition, OrderEnv } from "../scripts/order";
import { checkBalance } from "./utils/checkers";

/*
  Test cases list
  - work when rate = 0
  - work when rate > 0
  - work when rate < 0
  - rate increase
  - rate decrease
*/

describe("Funding rate", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let orderEnv: OrderEnv;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
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
    orderEnv = await getDefaultOrderEnv(context.dealer);
  });

  it("rate=0", async () => {
    await expect(
      context.dealer
        .connect(trader1)
        .updateFundingRate(
          [context.perpList[0].address],
          [utils.parseEther("0")]
        )
    ).to.be.revertedWith("JOJO_INVALID_FUNDING_RATE_KEEPER");
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("0")]
    );
    expect(
      await context.dealer.getFundingRate(context.perpList[0].address)
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

  it("rate>0", async () => {
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("1")]
    );
    expect(
      await context.dealer.getFundingRate(context.perpList[0].address)
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

  it("rate<0", async () => {
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("-1")]
    );
    expect(
      await context.dealer.getFundingRate(context.perpList[0].address)
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

  it("rate increase", async () => {
    await context.dealer.updateFundingRate(
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
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("-0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30014.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29996.5");
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30013.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29995.5");
  });

  it("rate decrease", async () => {
    await context.dealer.updateFundingRate(
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
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30015.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29997.5");
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("-0.5")]
    );
    await checkBalance(context.perpList[0], trader1.address, "1", "-30016.5");
    await checkBalance(context.perpList[0], trader2.address, "-1", "29998.5");
  });
});
