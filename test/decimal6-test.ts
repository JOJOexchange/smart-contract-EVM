import "./utils/hooks";
import { Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import {
  buildOrder,
  getDefaultOrderEnv,
  openPosition,
  OrderEnv,
  encodeTradeData,
} from "../scripts/order";
import BigNumber from "bignumber.js";

/*
  Check 
  - Funding rate
  - Oracle price 
*/

function shift6(num: string): string {
  return new BigNumber(num).multipliedBy(1000000).toString();
}

describe("decimal6", async () => {
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
    await context.priceSourceList[0].setMarkPrice(shift6("30000"));
    await context.priceSourceList[1].setMarkPrice(shift6("2000"));
    await context.priceSourceList[2].setMarkPrice(shift6("10"));
    await context.dealer
      .connect(trader1)
      .deposit(utils.parseEther("0"), shift6("10000"), trader1.address);
    await context.dealer
      .connect(trader2)
      .deposit(utils.parseEther("0"), shift6("10000"), trader2.address);
    let o1 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("1").toString(),
      shift6("-30000"),
      trader1
    );
    let o2 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("-1").toString(),
      shift6("30000"),
      trader2
    );
    let data = encodeTradeData(
      [o1.order, o2.order],
      [o1.signature, o2.signature],
      [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
    );
    await context.perpList[0].trade(data);
  });

  it("balance check", async () => {
    let trader1Credit = await context.dealer.getCreditOf(trader1Address);
    let trader2Credit = await context.dealer.getCreditOf(trader2Address);
    expect(trader1Credit.secondaryCredit).to.be.equal(shift6("10000"));
    expect(trader2Credit.secondaryCredit).to.be.equal(shift6("10000"));
    let trader1Risk = await context.dealer.getTraderRisk(trader1Address);
    let trader2Risk = await context.dealer.getTraderRisk(trader2Address);
    expect(trader1Risk.netValue).to.be.equal(shift6("9985"));
    expect(trader2Risk.netValue).to.be.equal(shift6("9997"));
    expect(trader1Risk.exposure).to.be.equal(shift6("30000"));
    expect(trader2Risk.exposure).to.be.equal(shift6("30000"));
    let trader1Balance = await context.perpList[0].balanceOf(trader1Address);
    let trader2Balance = await context.perpList[0].balanceOf(trader2Address);
    expect(trader1Balance.paper).to.be.equal(utils.parseEther("1"));
    expect(trader2Balance.paper).to.be.equal(utils.parseEther("-1"));
    expect(trader1Balance.credit).to.be.equal(shift6("-30015"));
    expect(trader2Balance.credit).to.be.equal(shift6("29997"));
    await context.dealer.updateFundingRate(
      [context.perpList[0].address],
      [utils.parseEther("1").add(shift6("10"))]
    );
    trader1Balance = await context.perpList[0].balanceOf(trader1Address);
    trader2Balance = await context.perpList[0].balanceOf(trader2Address);
    expect(trader1Balance.credit).to.be.equal(shift6("-30005"));
    expect(trader2Balance.credit).to.be.equal(shift6("29987"));
  });

  it("get liq price", async () => {
    let liqPrice1 = await context.dealer.getLiquidationPrice(
      trader1.address,
      context.perpList[0].address
    );
    let liqPrice2 = await context.dealer.getLiquidationPrice(
      trader2.address,
      context.perpList[0].address
    );
    expect(liqPrice1).to.be.equal("20634020618")
    expect(liqPrice2).to.be.equal("38832038834")
    await context.priceSourceList[0].setMarkPrice(shift6("40000"));
    expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.true
    expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.false
    await context.priceSourceList[0].setMarkPrice(shift6("20000"));
    expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.false
    expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.true
  });
});
