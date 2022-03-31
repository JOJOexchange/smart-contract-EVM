import { Contract, Wallet, utils } from "ethers";
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
    - check position
      - single position check
      - multi position check
      - position independent safe check
      - all position pnl summary
    - being liquidated
      - caused by funding ratio
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
        - funding ratio changed
    - handle bad debt

    Revert cases
    - can not liquidate safe trader
    - liquidator not safe
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
    await context.dealer.setVirtualCredit(
      trader1.address,
      utils.parseEther("5000")
    );
    await context.dealer.setVirtualCredit(
      trader2.address,
      utils.parseEther("5000")
    );
    await context.dealer.setVirtualCredit(
      liquidator.address,
      utils.parseEther("5000")
    );
    await context.dealer
      .connect(trader1)
      .deposit(utils.parseEther("5000"), trader1.address);
    await context.dealer
      .connect(trader2)
      .deposit(utils.parseEther("5000"), trader2.address);
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
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("21262"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[0].address
        )
      ).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[1].address
        )
      ).to.be.false;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[1].address
        )
      ).to.be.true;

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("38248"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[1].address
        )
      ).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[0].address
        )
      ).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[1].address
        )
      ).to.be.false;

      await context.priceSourceList[0].setMarkPrice(utils.parseEther("30000"));

      await context.priceSourceList[1].setMarkPrice(utils.parseEther("1213"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[1].address
        )
      ).to.be.false;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[1].address
        )
      ).to.be.true;

      await context.priceSourceList[1].setMarkPrice(utils.parseEther("2714"));
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader1.address,
          context.perpList[1].address
        )
      ).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[0].address
        )
      ).to.be.true;
      expect(
        await context.dealer.isPositionSafe(
          trader2.address,
          context.perpList[1].address
        )
      ).to.be.false;
    });
  });

  describe("being liquidated", async () => {
    it("caused by funding ratio", async () => {
      await openPosition(
        trader1,
        trader2,
        "10",
        "30000",
        context.perpList[0],
        orderEnv
      );
      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("-84")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("-85")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;

      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("98")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.true;
      await context.dealer.updateFundingRatio(
        [context.perpList[0].address],
        [utils.parseEther("99")]
      );
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      expect(await context.dealer.isSafe(trader2.address)).to.be.false;
    });
  });

  describe("execute liquidate", async () => {
    beforeEach(async () => {
      // liquidate trader1
      await openPosition(trader1, trader2, "1", "30000", perp0, orderEnv);
      // trader1 net value = 10000 - 15 = 9985
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("20600"));
      // trader1 net value = 9985 - 9400 = 585
    });
    it("single liquidation > total position", async () => {
      await perp0
        .connect(liquidator)
        .liquidate(trader1.address, utils.parseEther("2"));
      await checkBalance(perp0, liquidator.address, "1", "-20394");
      await checkBalance(perp0, trader1.address, "0", "0");
      await checkCredit(context, insurance, "203.94", "0");
      await checkCredit(context, trader1.address, "-4824.94", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });
    it("single liquidation = total position", async () => {
      await perp0
        .connect(liquidator)
        .liquidate(trader1.address, utils.parseEther("1"));
      await checkBalance(perp0, liquidator.address, "1", "-20394");
      await checkBalance(perp0, trader1.address, "0", "0");
      await checkCredit(context, insurance, "203.94", "0");
      await checkCredit(context, trader1.address, "-4824.94", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });
    it("single liquidation < total position", async () => {
      await perp0
        .connect(liquidator)
        .liquidate(trader1.address, utils.parseEther("0.01"));
      await checkBalance(perp0, liquidator.address, "0.01", "-203.94");
      await checkBalance(perp0, trader1.address, "0.99", "-29813.0994");
      await checkCredit(context, insurance, "2.0394", "0");
      await checkCredit(context, trader1.address, "5000", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
    });
    it("bad debt", async () => {
      await context.priceSourceList[0].setMarkPrice(utils.parseEther("19000"));
      await perp0
        .connect(liquidator)
        .liquidate(trader1.address, utils.parseEther("1"));
      await checkCredit(context, trader1.address, "-6393.1", "5000");
      expect(await context.dealer.isSafe(trader1.address)).to.be.false;
      expect(
        await context.dealer.isPositionSafe(trader1.address, perp0.address)
      ).to.be.true;
      await context.dealer.handleBadDebt(trader1.address);
      await checkCredit(context, insurance, "-6205", "0");
      expect(await context.dealer.isSafe(trader1.address)).to.be.true;
    });

    describe("return to safe before liquidate all position", async () => {
      it("partially liquidated", async () => {
        await perp0
          .connect(liquidator)
          .liquidate(trader1.address, utils.parseEther("0.99"));
        expect(await context.dealer.isSafe(trader1.address)).to.be.true;
      });
    });

    describe("revert cases", async () => {
      it("can not liquidate or bad debt safe trader", async () => {
        await context.priceSourceList[0].setMarkPrice(
          utils.parseEther("22000")
        );
        expect(
          perp0
            .connect(liquidator)
            .liquidate(trader1.address, utils.parseEther("0.01"))
        ).to.be.revertedWith("JOJO_ACCOUNT_IS_SAFE");
        expect(
          context.dealer.handleBadDebt(trader1.address)
        ).to.be.revertedWith("JOJO_ACCOUNT_IS_SAFE");
      });
      it("liquidator not safe", async () => {
        await context.dealer.setVirtualCredit(
          liquidator.address,
          utils.parseEther("0")
        );
        expect(
          perp0
            .connect(liquidator)
            .liquidate(trader1.address, utils.parseEther("0.01"))
        ).to.be.revertedWith("LIQUIDATOR_NOT_SAFE");
      });
      it("can not handle debt before liquidation finished", async () => {
        await perp0
          .connect(liquidator)
          .liquidate(trader1.address, utils.parseEther("0.01"));
        expect(
          context.dealer.handleBadDebt(trader1.address)
        ).to.be.revertedWith("JOJO_TRADER_STILL_IN_LIQUIDATION");
      });
    });
  });
});
