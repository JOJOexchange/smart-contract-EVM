import "./utils/hooks";
import { Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import {
  buildOrder,
  getDefaultOrderEnv,
  openPosition,
  OrderEnv,
} from "../scripts/order";

/*
  Test cases
  - getFundingRate
  - getAllRegisteredPerps
  - getCreditOf
  - getTraderRisk
  - getLiquidationPrice
*/

describe("view-functions", async () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let trader1Address: string;
  let trader2Address: string;
  let orderEnv: OrderEnv;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    trader1Address = await trader1.getAddress();
    trader2Address = await trader2.getAddress();
    orderEnv = await getDefaultOrderEnv(context.dealer);
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("10000"),
        trader1.address
      );
    await context.dealer
      .connect(trader2)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("10000"),
        trader2.address
      );
    await openPosition(
      trader1,
      trader2,
      "1",
      "30000",
      context.perpList[0],
      orderEnv
    );
    await openPosition(
      trader1,
      trader2,
      "10",
      "2000",
      context.perpList[1],
      orderEnv
    );
  });

  it("get funding rate", async () => {
    await context.dealer.updateFundingRate(
      [context.perpList[1].address],
      [utils.parseEther("10")]
    );
    expect(
      await context.dealer.getFundingRate(context.perpList[1].address)
    ).to.equal(utils.parseEther("10"));
    expect(
      await context.dealer.getFundingRate(context.perpList[0].address)
    ).to.equal(utils.parseEther("1"));
  });

  it("get registered perp", async () => {
    let perpList: string[] = await context.dealer.getAllRegisteredPerps();
    await expect(perpList[0]).to.equal(context.perpList[0].address);
    await expect(perpList[1]).to.equal(context.perpList[1].address);
    await expect(perpList[2]).to.equal(context.perpList[2].address);
  });

  it("get trader risk", async () => {
    await context.priceSourceList[0].setMarkPrice(utils.parseEther("35000"));
    await context.priceSourceList[1].setMarkPrice(utils.parseEther("1800"));
    const risk1 = await context.dealer.getTraderRisk(trader1.address);
    const risk2 = await context.dealer.getTraderRisk(trader2.address);
    // risk1
    // netvalue = 10000-15-10+5000-2000 = 12975
    // exposure = 35000+18000 = 53000
    // maintenanceMargin = 35000*0.03+18000*0.05 = 1950
    await expect(risk1.netValue).to.be.equal(utils.parseEther("12975"));
    await expect(risk1.exposure).to.be.equal(utils.parseEther("53000"));
    await expect(risk1.maintenanceMargin).to.be.equal(utils.parseEther("1950"));
    // risk2
    // netvalue = 10000-3-2-5000+2000 = 6995
    // exposure = 35000+18000 = 53000
    // maintenanceMargin = 35000*0.03+18000*0.05 = 1950
    await expect(risk2.netValue).to.be.equal(utils.parseEther("6995"));
    await expect(risk2.exposure).to.be.equal(utils.parseEther("53000"));
    await expect(risk1.maintenanceMargin).to.be.equal(utils.parseEther("1950"));
  });

  it("get trader risk & liq price", async () => {
    await expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[0].address
      )
    ).to.be.equal("21675257731958762886597");
    await expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[1].address
      )
    ).to.be.equal("1150000000000000000000");
    await expect(
      await context.dealer.getLiquidationPrice(
        trader2.address,
        context.perpList[0].address
      )
    ).to.be.equal("37859223300970873786407");
    await expect(
      await context.dealer.getLiquidationPrice(
        trader2.address,
        context.perpList[1].address
      )
    ).to.be.equal("2770952380952380952380");
  });

  it("can not get valid liq price", async () => {
    // 1. no position
    await expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[2].address
      )
    ).to.be.equal("0");
    // 2. mul to 0 because of position too small
    await openPosition(
      trader1,
      trader2,
      "0.000000000000000001",
      "5",
      context.perpList[2],
      orderEnv
    );
    await expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[2].address
      )
    ).to.be.equal("0");
    // 3. small long position always safe
    await openPosition(
      trader1,
      trader2,
      "10",
      "5",
      context.perpList[2],
      orderEnv
    );
    await expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[2].address
      )
    ).to.be.equal("0");
  });

  it("get risk params", async () => {
    let params = await context.dealer.getRiskParams(
      context.perpList[0].address
    );
    await expect(params.liquidationThreshold).to.be.equal(
      utils.parseEther("0.03")
    );
    await expect(params.liquidationPriceOff).to.be.equal(
      utils.parseEther("0.01")
    );
    await expect(params.insuranceFeeRate).to.be.equal(utils.parseEther("0.01"));
    await expect(params.markPriceSource).to.be.equal(
      context.priceSourceList[0].address
    );
    await expect(params.name).to.be.equal("BTC20x");
    await expect(params.isRegistered).to.be.true;
  });

  it("get positions", async () => {
    let positions = await context.dealer.getPositions(trader1.address);
    await expect(positions.length).to.be.equal(2);
    positions = await context.dealer.getPositions(trader2.address);
    await expect(positions.length).to.be.equal(2);
    await openPosition(
      trader2,
      trader1,
      "10",
      "2000",
      context.perpList[1],
      orderEnv
    );
    positions = await context.dealer.getPositions(trader1.address);
    await expect(positions.length).to.be.equal(1);
    positions = await context.dealer.getPositions(trader2.address);
    await expect(positions.length).to.be.equal(1);
    await openPosition(
      trader2,
      trader1,
      "1",
      "30000",
      context.perpList[0],
      orderEnv
    );

    positions = await context.dealer.getPositions(trader1.address);
    await expect(positions.length).to.be.equal(0);
    positions = await context.dealer.getPositions(trader2.address);
    await expect(positions.length).to.be.equal(0);
  });

  it("get version", async () => {
    let version = await context.dealer.version();
    await expect(version).to.be.equal("JOJODealer V1.1");
  });

  it("get mark price", async () => {
    let markPrice = await context.dealer.getMarkPrice(
      context.perpList[1].address
    );
    await expect(markPrice).to.be.equal(utils.parseEther("2000"));
  });
});
