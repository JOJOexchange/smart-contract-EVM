import "./utils/hooks";
import { Wallet, utils } from "ethers";
import { expect } from "chai";
import {
  basicContext,
  Context,
  fundTrader,
  setPrice,
} from "../scripts/context";
import {
  checkCredit,
  checkPrimaryAsset,
  checkSecondaryAsset,
} from "./utils/checkers";
import { timeJump } from "./utils/timemachine";
import { getDefaultOrderEnv, openPosition } from "../scripts/order";

/*
  Test cases list
  - deposit
    - deposit to others
  - withdraw
    - withdraw without timelock
    - withdraw with timelock
  - withdrawal can make primary credit negative

  Revert cases list
  - withdraw when being liquidated
  - withdraw when not enough balance
*/

describe("Funding", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let trader1Address: string;
  let trader2Address: string;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    trader1Address = await trader1.getAddress();
    trader2Address = await trader2.getAddress();
  });

  describe("funding", async () => {
    it("deposit", async () => {
      let c = context.dealer.connect(trader1);
      // deposit to self
      await c.deposit(
        utils.parseEther("100000"),
        utils.parseEther("500000"),
        trader1Address
      );
      await checkPrimaryAsset(context, trader1Address, "900000");
      await checkPrimaryAsset(context, context.dealer.address, "100000");
      await checkSecondaryAsset(context, trader1Address, "500000");
      await checkSecondaryAsset(context, context.dealer.address, "500000");
      await checkCredit(context, trader1Address, "100000", "500000");

      // deposit to others
      await c.deposit(
        utils.parseEther("20000"),
        utils.parseEther("10000"),
        trader2Address
      );
      await checkPrimaryAsset(context, trader1Address, "880000");
      await checkPrimaryAsset(context, context.dealer.address, "120000");
      await checkSecondaryAsset(context, trader1Address, "490000");
      await checkSecondaryAsset(context, context.dealer.address, "510000");
      await checkCredit(context, trader2Address, "20000", "10000");

      // only deposit primary asset
      await c.deposit(
        utils.parseEther("10000"),
        utils.parseEther("0"),
        trader1Address
      );
      await checkPrimaryAsset(context, trader1Address, "870000");
      await checkPrimaryAsset(context, context.dealer.address, "130000");
      await checkSecondaryAsset(context, trader1Address, "490000");
      await checkSecondaryAsset(context, context.dealer.address, "510000");
      await checkCredit(context, trader1Address, "110000", "500000");

      // only deposit secondary asset
      await c.deposit(
        utils.parseEther("0"),
        utils.parseEther("10000"),
        trader1Address
      );
      await checkPrimaryAsset(context, trader1Address, "870000");
      await checkPrimaryAsset(context, context.dealer.address, "130000");
      await checkSecondaryAsset(context, trader1Address, "480000");
      await checkSecondaryAsset(context, context.dealer.address, "520000");
      await checkCredit(context, trader1Address, "110000", "510000");
    });
  });

  describe("withdraw", async () => {
    it("with timelock", async () => {
      await context.dealer.setWithdrawTimeLock("100");
      const state = await context.dealer.state();
      expect(state.withdrawTimeLock).to.equal("100");

      let d = context.dealer.connect(trader1);
      await d.deposit(
        utils.parseEther("100000"),
        utils.parseEther("100000"),
        trader1Address
      );
      await d.requestWithdraw(
        utils.parseEther("30000"),
        utils.parseEther("20000")
      );
      await checkCredit(context, trader1Address, "100000", "100000");
      await checkPrimaryAsset(context, trader1Address, "900000");
      await checkSecondaryAsset(context, trader1Address, "900000");

      const creditInfo = await context.dealer.getCreditOf(trader1Address);
      expect(creditInfo[2]).to.be.equal(utils.parseEther("30000"));
      expect(creditInfo[3]).to.be.equal(utils.parseEther("20000"));

      await timeJump(50);
      expect(d.executeWithdraw(trader1Address, false)).to.be.revertedWith(
        "JOJO_WITHDRAW_PENDING"
      );

      await timeJump(100);
      await d.executeWithdraw(trader1Address, false);
      await checkCredit(context, trader1Address, "70000", "80000");
      await checkPrimaryAsset(context, trader1Address, "930000");
      await checkSecondaryAsset(context, trader1Address, "920000");
    });

    it("withdraw primary asset to negative", async () => {
      await context.dealer
        .connect(trader1)
        .deposit(
          utils.parseEther("0"),
          utils.parseEther("1000000"),
          trader1Address
        );
      await context.dealer
        .connect(trader2)
        .deposit(
          utils.parseEther("1000000"),
          utils.parseEther("0"),
          trader2Address
        );
      await openPosition(
        trader1,
        trader2,
        "100",
        "30000",
        context.perpList[0],
        await getDefaultOrderEnv(context.dealer)
      );
      await setPrice(context.priceSourceList[0], "30100");
      await context.dealer
        .connect(trader1)
        .requestWithdraw(utils.parseEther("1000"), utils.parseEther("0"));
      await context.dealer
        .connect(trader1)
        .executeWithdraw(trader1.address, false);
      await checkCredit(context, trader1Address, "-1000", "1000000");

      await context.dealer
        .connect(trader1)
        .requestWithdraw(utils.parseEther("0"), utils.parseEther("900000"));
      expect(
        context.dealer.connect(trader1).executeWithdraw(trader1.address, false)
      ).to.be.revertedWith("JOJO_ACCOUNT_NOT_SAFE");
    });

    it("internal transfer", async () => {
      await context.dealer
        .connect(trader1)
        .deposit(
          utils.parseEther("1000000"),
          utils.parseEther("1000000"),
          trader1Address
        );
      await context.dealer
        .connect(trader1)
        .requestWithdraw(
          utils.parseEther("500000"),
          utils.parseEther("200000")
        );
      await context.dealer
        .connect(trader1)
        .executeWithdraw(trader2.address, true);
      await checkCredit(context, trader1Address, "500000", "800000");
      await checkCredit(context, trader2Address, "500000", "200000");
      await checkPrimaryAsset(context, trader1Address, "0");
      await checkSecondaryAsset(context, trader1Address, "0");
      await checkPrimaryAsset(context, trader2Address, "1000000");
      await checkSecondaryAsset(context, trader2Address, "1000000");
    });
  });

  describe("Other revert cases", async () => {
    it("solid safe check", async () => {
      await context.dealer
        .connect(trader2)
        .deposit(
          utils.parseEther("100"),
          utils.parseEther("0"),
          trader2Address
        );
      let d = context.dealer.connect(trader1);
      await d.deposit(
        utils.parseEther("100000"),
        utils.parseEther("100000"),
        trader1Address
      );
      await d.requestWithdraw(
        utils.parseEther("100001"),
        utils.parseEther("0")
      );
      await expect(d.executeWithdraw(trader1Address, false)).to.be.revertedWith(
        "JOJO_ACCOUNT_NOT_SAFE"
      );
    });
  });
});
