import "./utils/hooks";
import { Contract, Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import { getDefaultOrderEnv, openPosition, OrderEnv } from "../scripts/order";
import { checkBalance, checkCredit } from "./utils/checkers";

/*
    Test cases list
    - check position
      - single position check
      - multi position check
      - position independent safe check
      - all position pnl summary
    - being liquidated
      - caused by funding rate
      - caused by mark price change
    - liquidate price
        - single liquidation > total position
        - single liquidation = total position
        - single liquidation < total position
        - change with mark price
    - execute liquidation
        - balance
        - insurance fee
        - bad debt
    - return to safe before liquidate all position
        - partially liquidated
        - mark price changed
        - funding rate changed
    - handle bad debt

    Revert cases
    - can not liquidate safe trader
    - liquidator not safe
    - self liquidation
    - safe account can not be handleDebt
    - can not handle debt before liquidation finished
*/

describe("Liquidation", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let liquidator: Wallet;
  let orderEnv: OrderEnv;
  let insurance: string;
  let perp0: Contract;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    liquidator = context.traderList[2];
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("5000"),
        liquidator.address
      );
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("5000"),
        utils.parseEther("5000"),
        trader1.address
      );
    await context.dealer
      .connect(trader2)
      .deposit(
        utils.parseEther("5000"),
        utils.parseEther("5000"),
        trader2.address
      );
    orderEnv = await getDefaultOrderEnv(context.dealer);
    insurance = await context.insurance.getAddress();
    perp0 = context.perpList[0];
  });

  describe("check position", async () => {
    it("single position check", async () => {
      await openPosition(
        trader1,
        trader2,
        "1",
        "30000",
        context.perpList[0],
        orderEnv
      );

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("39000"));
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("20000"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
    });

    it("multi position check", async () => {
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

      // trader1 BTC liqPrice 21675.257731958762886597
      // trader2 BTC liqPrice 37859.223300970873786407
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("21676"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("21675"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("37859"));
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("37860"));
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("30000"));

      // trader1 ETH liqPrice 1150
      // trader2 ETH liqPrice 2770.952380952380952380
      await context.priceSourceList[1].setMarkPrice(utils.parseEther("1150"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      await context.priceSourceList[1].setMarkPrice(utils.parseEther("1149"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;

      await context.priceSourceList[1].setMarkPrice(utils.parseEther("2770"));
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.priceSourceList[1].setMarkPrice(utils.parseEther("2771"));
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
    });
  });

  describe("being liquidated", async () => {
    it("caused by funding rate", async () => {
      await openPosition(
        trader1,
        trader2,
        "10",
        "30000",
        context.perpList[0],
        orderEnv
      );
      await context.dealer.updateFundingRate(
        [context.perpList[0].address],
        [utils.parseEther("-84")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.dealer.updateFundingRate(
        [context.perpList[0].address],
        [utils.parseEther("-85")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;

      await context.dealer.updateFundingRate(
        [context.perpList[0].address],
        [utils.parseEther("98")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.dealer.updateFundingRate(
        [context.perpList[0].address],
        [utils.parseEther("99")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
    });
  });

  describe("execute liquidation", async () => {
    beforeEach(async () => {
      // liquidate trader1
      await openPosition(trader1, trader2, "1", "30000", perp0, orderEnv);
      // trader1 net value = 10000 - 15 = 9985
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("20600"));
      // trader1 net value = 9985 - 9400 = 585
    });
    it("operator call liquidation", async () => {
      let operator = trader2;
      await expect(
        perp0
          .connect(operator)
          .liquidate(
            liquidator.address,
            trader1.address,
            utils.parseEther("0.01"),
            utils.parseEther("-500")
          )
      ).to.be.revertedWith("JOJO_INVALID_LIQUIDATION_EXECUTOR");
      await context.dealer
        .connect(liquidator)
        .setOperator(operator.address, true);
      await perp0
        .connect(operator)
        .liquidate(
          liquidator.address,
          trader1.address,
          utils.parseEther("2"),
          utils.parseEther("-50000")
        );
      await checkBalance(perp0, liquidator.address, "1", "-20394");
      await checkBalance(perp0, trader1.address, "0", "0");
      await checkCredit(context, insurance, "203.94", "0");
      await checkCredit(context, trader1.address, "-4824.94", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });
    it("single liquidation > total position", async () => {
      const liquidatorChange = await context.dealer.getLiquidationCost(
        perp0.address,
        trader1.address,
        utils.parseEther("2")
      );
      expect(liquidatorChange.liqtorPaperChange).to.be.equal(
        utils.parseEther("1")
      );
      expect(liquidatorChange.liqtorCreditChange).to.be.equal(
        utils.parseEther("-20394")
      );
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader1.address,
          utils.parseEther("2"),
          utils.parseEther("-50000")
        );
      await checkBalance(perp0, liquidator.address, "1", "-20394");
      await checkBalance(perp0, trader1.address, "0", "0");
      await checkCredit(context, insurance, "203.94", "0");
      await checkCredit(context, trader1.address, "-4824.94", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });
    it("single liquidation = total position", async () => {
      const liquidatorChange = await context.dealer.getLiquidationCost(
        perp0.address,
        trader1.address,
        utils.parseEther("1")
      );
      expect(liquidatorChange.liqtorPaperChange).to.be.equal(
        utils.parseEther("1")
      );
      expect(liquidatorChange.liqtorCreditChange).to.be.equal(
        utils.parseEther("-20394")
      );
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader1.address,
          utils.parseEther("1"),
          utils.parseEther("-25000")
        );
      await checkBalance(perp0, liquidator.address, "1", "-20394");
      await checkBalance(perp0, trader1.address, "0", "0");
      await checkCredit(context, insurance, "203.94", "0");
      await checkCredit(context, trader1.address, "-4824.94", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      // console.log(
      //   await context.dealer.getLiquidationPrice(
      //     liquidator.address,
      //     perp0.address
      //   )
      // );
    });
    it("single liquidation < total position", async () => {
      const liquidatorChange = await context.dealer.getLiquidationCost(
        perp0.address,
        trader1.address,
        utils.parseEther("0.01")
      );
      expect(liquidatorChange.liqtorPaperChange).to.be.equal(
        utils.parseEther("0.01")
      );
      expect(liquidatorChange.liqtorCreditChange).to.be.equal(
        utils.parseEther("-203.94")
      );
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader1.address,
          utils.parseEther("0.01"),
          utils.parseEther("-250")
        );
      await checkBalance(perp0, liquidator.address, "0.01", "-203.94");
      await checkBalance(perp0, trader1.address, "0.99", "-29813.0994");
      await checkCredit(context, insurance, "2.0394", "0");
      await checkCredit(context, trader1.address, "5000", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      await expect(
        perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader1.address,
            utils.parseEther("2"),
            utils.parseEther("-40000")
          )
      ).to.be.revertedWith("LIQUIDATION_PRICE_PROTECTION");
    });
    it("single liquidation > total position: short position", async () => {
      // trader2 net value = 10000 - 3 = 9997
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("39000"));
      // trader2 net value = 9997 - 9000 = 997
      const liquidatorChange = await context.dealer.getLiquidationCost(
        perp0.address,
        trader2.address,
        utils.parseEther("-2")
      );
      expect(liquidatorChange.liqtorPaperChange).to.be.equal(
        utils.parseEther("-1")
      );
      expect(liquidatorChange.liqtorCreditChange).to.be.equal(
        utils.parseEther("39390")
      );
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader2.address,
          utils.parseEther("-2"),
          utils.parseEther("50000")
        );
      await checkBalance(perp0, liquidator.address, "-1", "39390");
      await checkBalance(perp0, trader2.address, "0", "0");
      await checkCredit(context, insurance, "393.9", "0");
      await checkCredit(context, trader2.address, "-4786.9", "5000");
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
    });
    it("single liquidation < total position: short position", async () => {
      // trader2 net value = 10000 - 3 = 9997
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("39000"));
      // trader2 net value = 9997 - 9000 = 997
      const liquidatorChange = await context.dealer.getLiquidationCost(
        perp0.address,
        trader2.address,
        utils.parseEther("-0.01")
      );
      expect(liquidatorChange.liqtorPaperChange).to.be.equal(
        utils.parseEther("-0.01")
      );
      expect(liquidatorChange.liqtorCreditChange).to.be.equal(
        utils.parseEther("393.9")
      );
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader2.address,
          utils.parseEther("-0.01"),
          utils.parseEther("300")
        );
      await checkBalance(perp0, liquidator.address, "-0.01", "393.9");
      await checkBalance(perp0, trader2.address, "-0.99", "29599.161");
      await checkCredit(context, insurance, "3.939", "0");
      await checkCredit(context, trader2.address, "5000", "5000");
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
      await expect(
        perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader2.address,
            utils.parseEther("-2"),
            utils.parseEther("80000")
          )
      ).to.be.revertedWith("LIQUIDATION_PRICE_PROTECTION");
      await expect(
        perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader2.address,
            utils.parseEther("2"),
            utils.parseEther("-80000")
          )
      ).to.be.revertedWith("JOJO_LIQUIDATION_REQUEST_AMOUNT_WRONG");
    });
    it("bad debt", async () => {
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("19000"));
      await perp0
        .connect(liquidator)
        .liquidate(
          liquidator.address,
          trader1.address,
          utils.parseEther("1"),
          utils.parseEther("-50000")
        );
      await checkCredit(context, trader1.address, "0", "0");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      await expect(
        perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader1.address,
            utils.parseEther("1"),
            utils.parseEther("-50000")
          )
      ).to.be.revertedWith("JOJO_ACCOUNT_IS_SAFE");
      await checkCredit(context, insurance, "-6205", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });

    describe("return to safe before liquidate all position", async () => {
      it("partially liquidated", async () => {
        await perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader1.address,
            utils.parseEther("0.99"),
            utils.parseEther("-50000")
          );
        expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      });
    });

    describe("other revert cases", async () => {
      it("can not liquidate or bad debt safe trader", async () => {
        await context.priceSourceList[0].setMarkPrice(
          utils.parseEther("22000")
        );
        await expect(
          perp0
            .connect(liquidator)
            .liquidate(
              liquidator.address,
              trader1.address,
              utils.parseEther("0.01"),
              utils.parseEther("-500")
            )
        ).to.be.revertedWith("JOJO_ACCOUNT_IS_SAFE");
      });
      it("liquidator not safe", async () => {
        await context.dealer
          .connect(liquidator)
          .requestWithdraw(liquidator.address, utils.parseEther("0"), utils.parseEther("5000"));
        await context.dealer
          .connect(liquidator)
          .executeWithdraw(liquidator.address, liquidator.address, false, Buffer.from([]));
        await expect(
          perp0
            .connect(liquidator)
            .liquidate(
              liquidator.address,
              trader1.address,
              utils.parseEther("0.01"),
              utils.parseEther("-500")
            )
        ).to.be.revertedWith("LIQUIDATOR_NOT_SAFE");
      });
      it("self liquidation", async () => {
        await expect(
          perp0
            .connect(trader1)
            .liquidate(
              trader1.address,
              trader1.address,
              utils.parseEther("0.01"),
              utils.parseEther("-500")
            )
        ).to.be.revertedWith("JOJO_SELF_LIQUIDATION_NOT_ALLOWED");
      });
      it("trader is not safe but don't have certain position", async () => {
        await expect(
          context.perpList[1]
            .connect(liquidator)
            .liquidate(
              liquidator.address,
              trader1.address,
              utils.parseEther("0.01"),
              utils.parseEther("-500")
            )
        ).to.be.revertedWith("JOJO_TRADER_HAS_NO_POSITION");
      });
      it("can not handle debt before liquidation finished", async () => {
        await perp0
          .connect(liquidator)
          .liquidate(
            liquidator.address,
            trader1.address,
            utils.parseEther("0.01"),
            utils.parseEther("-500")
          );
      });
    });
  });
});
