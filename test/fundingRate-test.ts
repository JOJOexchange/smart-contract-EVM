import "./utils/hooks";
import { ethers } from "hardhat";
import { Contract, Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import { getDefaultOrderEnv, openPosition, OrderEnv } from "../scripts/order";
import { checkBalance } from "./utils/checkers";
import { timeJump } from "./utils/timemachine";

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

  it("revert cases", async () => {
    await expect(
      context.dealer.updateFundingRate(
        [context.perpList[0].address],
        [utils.parseEther("0.5"), utils.parseEther("1")]
      )
    ).to.be.revertedWith("JOJO_ARRAY_LENGTH_NOT_SAME");
  });

  it.only("limiter", async () => {
    let limiter: Contract = await (
      await ethers.getContractFactory("FundingRateUpdateLimiter")
    ).deploy(context.dealer.address, 3);

    let perps = [
      context.perpList[0].address,
      context.perpList[1].address,
      context.perpList[2].address,
    ];
    await context.dealer.setFundingRateKeeper(limiter.address);
    await limiter.updateFundingRate(perps, [
      utils.parseEther("1"),
      utils.parseEther("2"),
      utils.parseEther("3"),
    ]);
    expect(await context.perpList[0].getFundingRate()).to.be.equal(utils.parseEther("1"))
    expect(await context.perpList[1].getFundingRate()).to.be.equal(utils.parseEther("2"))
    expect(await context.perpList[2].getFundingRate()).to.be.equal(utils.parseEther("3"))

    await timeJump(86400);
    expect(await limiter.getMaxChange(context.perpList[0].address)).to.be.equal(utils.parseEther("2700"))
    expect(await limiter.getMaxChange(context.perpList[1].address)).to.be.equal(utils.parseEther("300"))
    expect(await limiter.getMaxChange(context.perpList[2].address)).to.be.equal(utils.parseEther("3"))

    await expect(limiter.updateFundingRate([context.perpList[0].address], [utils.parseEther("2702")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")
    await expect(limiter.updateFundingRate([context.perpList[1].address], [utils.parseEther("303")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")
    await expect(limiter.updateFundingRate([context.perpList[2].address], [utils.parseEther("7")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")

    await expect(limiter.updateFundingRate([context.perpList[0].address], [utils.parseEther("-2700")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")
    await expect(limiter.updateFundingRate([context.perpList[1].address], [utils.parseEther("-299")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")
    await expect(limiter.updateFundingRate([context.perpList[2].address], [utils.parseEther("-1")])).to.be.revertedWith("FUNDING_RATE_CHANGE_TOO_MUCH")

    await limiter.updateFundingRate(perps, [
      utils.parseEther("2701"),
      utils.parseEther("302"),
      utils.parseEther("6"),
    ]);
    // console.log(
    //   await limiter.fundingRateUpdateTimestamp(context.perpList[0].address)
    // );
  });
});
