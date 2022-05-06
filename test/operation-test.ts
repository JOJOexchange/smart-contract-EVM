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

    await context.dealer.setPerpRiskParams(context.perpList[1].address, [
      utils.parseEther("0.05"), // 5% liquidation
      utils.parseEther("0.01"), // 1% price offset
      // utils.parseEther("1000"), // 1000ETH max
      utils.parseEther("0.01"), // 1% insurance fee
      utils.parseEther("1"), // init funding rate 1
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
});
