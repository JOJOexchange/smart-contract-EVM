import "./utils/hooks"
import { Wallet, utils } from "ethers";
import { expect } from "chai";
import {
  basicContext,
  Context,
} from "../scripts/context";
import { buildOrder, getDefaultOrderEnv, openPosition, OrderEnv } from "../scripts/order";

/*
  Test cases
  - getFundingRatio
  - getRegisteredPerp
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
    await context.dealer.setVirtualCredit(
      trader1.address,
      utils.parseEther("10000")
    );
    await context.dealer.setVirtualCredit(
      trader2.address,
      utils.parseEther("10000")
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

  it("get funding ratio", async () => {
    await context.dealer.updateFundingRatio(
      [context.perpList[1].address],
      [utils.parseEther("10")]
    );
    expect(
      await context.dealer.getFundingRatio(context.perpList[1].address)
    ).to.equal(utils.parseEther("10"));
    expect(
      await context.dealer.getFundingRatio(context.perpList[0].address)
    ).to.equal(utils.parseEther("1"));
  });

  it("get registered perp",async () => {
    let perpList:string[] = await context.dealer.getRegisteredPerp()
    expect(perpList[0]).to.equal(context.perpList[0].address)
    expect(perpList[1]).to.equal(context.perpList[1].address)
    expect(perpList[2]).to.equal(context.perpList[2].address)
  })

  it("get trader risk",async()=>{
    await context.priceSourceList[0].setMarkPrice(utils.parseEther("35000"));
    await context.priceSourceList[1].setMarkPrice(utils.parseEther("1800"));
    const risk1 = await context.dealer.getTraderRisk(trader1.address)
    const risk2 = await context.dealer.getTraderRisk(trader2.address)
    // risk1
    // netvalue = 10000-15-10+5000-2000 = 12975
    // exposure = 35000+18000 = 53000
    expect(risk1.netValue).to.be.equal(utils.parseEther("12975"))
    expect(risk1.exposure).to.be.equal(utils.parseEther("53000"))
    // risk2
    // netvalue = 10000-3-2-5000+2000 = 6995
    // exposure = 35000+18000 = 53000
    expect(risk2.netValue).to.be.equal(utils.parseEther("6995"))
    expect(risk2.exposure).to.be.equal(utils.parseEther("53000"))
  })

  it("get trader risk & liq price", async () => {
    expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[0].address
      )
    ).to.be.equal("21262886597938144329896");
    expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[1].address
      )
    ).to.be.equal("1213157894736842105263");
    expect(
      await context.dealer.getLiquidationPrice(
        trader2.address,
        context.perpList[0].address
      )
    ).to.be.equal("38247572815533980582524");
    expect(
      await context.dealer.getLiquidationPrice(
        trader2.address,
        context.perpList[1].address
      )
    ).to.be.equal("2713809523809523809523");
  });

  it("can not get valid liq price",async () => {
    // 1. no position
    expect(
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
    expect(
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
    expect(
      await context.dealer.getLiquidationPrice(
        trader1.address,
        context.perpList[2].address
      )
    ).to.be.equal("0");
  })

  it("get order hash",async () => {
    let o = await buildOrder(
      await getDefaultOrderEnv(context.dealer),
      context.perpList[0].address,
      utils.parseEther("1").toString(),
      utils.parseEther("-30000").toString(),
      context.traderList[0],
    )
    expect(await context.dealer.getOrderHash(o.order)).to.be.equal(o.hash)
  })

  it("get risk params",async () => {
    let params = await context.dealer.getRiskParams(context.perpList[0].address)
    expect(params.liquidationThreshold).to.be.equal(utils.parseEther("0.03"))
    expect(params.liquidationPriceOff).to.be.equal(utils.parseEther("0.01"))
    expect(params.insuranceFeeRate).to.be.equal(utils.parseEther("0.01"))
    expect(params.fundingRatio).to.be.equal(utils.parseEther("1"))
    expect(params.markPriceSource).to.be.equal(context.priceSourceList[0].address)
    expect(params.name).to.be.equal("BTC20x")
    expect(params.isRegistered).to.be.true
  })
});


