import { expect } from "chai";
import { utils } from "ethers";
import { basicContext, Context } from "../scripts/context";
import "./utils/hooks";

/*
    Most operation functions has already been tested in other files.
    We will only add very few test missed before
    - remove perp
*/

describe("operations", async () => {
  let context: Context;
  before(async () => {
    context = await basicContext();
  });

  it("remove perp", async () => {
    let registeredPerps = await context.dealer.getAllRegisteredPerps();
    await expect(registeredPerps[0]).to.be.equal(context.perpList[0].address);
    await expect(registeredPerps[1]).to.be.equal(context.perpList[1].address);
    await expect(registeredPerps[2]).to.be.equal(context.perpList[2].address);
    await expect(registeredPerps.length).to.be.equal(3);

    await context.dealer.setPerpRiskParams(context.perpList[1].address, [
      utils.parseEther("0.10"), // 10% initial
      utils.parseEther("0.05"), // 5% liquidation
      utils.parseEther("0.01"), // 1% price offset
      // utils.parseEther("1000"), // 1000ETH max
      utils.parseEther("0.01"), // 1% insurance fee
      // utils.parseEther("1"), // init funding rate 1
      context.perpList[1].address, // mark price source
      "ETH10x", // name
      false, // register
    ]);

    registeredPerps = await context.dealer.getAllRegisteredPerps();
    await expect(registeredPerps[0]).to.be.equal(context.perpList[0].address);
    await expect(registeredPerps[1]).to.be.equal(context.perpList[2].address);
    await expect(registeredPerps.length).to.be.equal(2);
  });

  it("set order sender", async () => {
    let traderAddress = context.traderList[0].address;
    await expect(await context.dealer.isOrderSenderValid(traderAddress)).to.be
      .false;
    await context.dealer.setOrderSender(traderAddress, true);
    await expect(await context.dealer.isOrderSenderValid(traderAddress)).to.be
      .true;
    await context.dealer.setOrderSender(traderAddress, false);
    await expect(await context.dealer.isOrderSenderValid(traderAddress)).to.be
      .false;
  });

  it("only registered perp",async () => {
    await expect(
      context.dealer.approveTrade(context.traderList[0].address, "0x00")
    ).to.be.revertedWith("JOJO_PERP_NOT_REGISTERED");

    await expect(
      context.dealer.requestLiquidation(context.traderList[0].address, context.traderList[1].address, context.traderList[0].address, 0)
    ).to.be.revertedWith("JOJO_PERP_NOT_REGISTERED");

    await expect(
      context.dealer.openPosition(context.traderList[0].address)
    ).to.be.revertedWith("JOJO_PERP_NOT_REGISTERED");

    await expect(
      context.dealer.realizePnl(context.traderList[0].address, 0)
    ).to.be.revertedWith("JOJO_PERP_NOT_REGISTERED");
  })

  it("invalid risk param",async () => {
    await expect(
      context.dealer.setPerpRiskParams(context.perpList[0].address, [
        utils.parseEther("0.05"), // 5% initial
        utils.parseEther("0.03"), // 3% liquidation
        utils.parseEther("0.02"), // 1% price offset
        utils.parseEther("0.02"), // 1% insurance fee
        context.priceSourceList[0].address, // mark price source
        "BTC20x", // name
        true, // register
      ])
    ).to.be.revertedWith("JOJO_INVALID_RISK_PARAM");
  })

  it("secondary asset can not be changed",async () => {
    await expect(
      context.dealer.setSecondaryAsset(context.secondaryAsset.address)
    ).to.be.revertedWith("JOJO_SECONDARY_ASSET_ALREADY_EXIST")
  })
});
