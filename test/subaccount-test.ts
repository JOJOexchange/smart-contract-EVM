import "./utils/hooks";
import { expect } from "chai";
import { Contract, utils, Wallet } from "ethers";
import { ethers } from "hardhat";
import { basicContext, Context } from "../scripts/context";
import {
  buildOrder,
  encodeTradeData,
  getDefaultOrderEnv,
  OrderEnv,
} from "../scripts/order";
import {
  checkBalance,
  checkCredit,
  checkPrimaryAsset,
  checkSecondaryAsset,
} from "./utils/checkers";
import { timeJump } from "./utils/timemachine";
import { parseEther } from "ethers/lib/utils";

/*
    Test cases list
    - create subaccount
    - withdraw
    - withdrawPending
    - trade
*/

describe("Subaccount", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let orderEnv: OrderEnv;
  let registry: Contract;
  let trader1Sub: Contract;
  let trader2Sub: Contract;
  let op: Wallet;
  before(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    op = context.traderList[2];
    orderEnv = await getDefaultOrderEnv(context.dealer);

    registry = await (
      await ethers.getContractFactory("SubaccountFactory")
    ).deploy(context.dealer.address);

    await registry.connect(trader1).newSubaccount();
    await registry.connect(trader1).newSubaccount();
    await registry.connect(trader1).newSubaccount();
    await registry.connect(trader2).newSubaccount();
    await registry.connect(trader2).newSubaccount();
    await registry.connect(trader2).newSubaccount();

    let subaccountFactory = await ethers.getContractFactory("Subaccount");
    trader1Sub = await subaccountFactory.attach(
      (
        await registry.getSubaccounts(trader1.address)
      )[0]
    );
    trader2Sub = await subaccountFactory.attach(
      (
        await registry.getSubaccounts(trader2.address)
      )[0]
    );

    await trader1Sub.connect(trader1).setOperator(op.address, true);
    await trader2Sub.connect(trader2).setOperator(op.address, true);
  });

  it("check registry", async () => {
    const trader1Subaccount = await registry.getSubaccounts(trader1.address);
    const trader2Subaccount = await registry.getSubaccounts(trader2.address);
    expect(trader1Subaccount.length).to.be.equal(3);
    expect(trader2Subaccount.length).to.be.equal(3);
  });

  it("set op", async () => {
    expect(await context.dealer.isOperatorValid(trader1Sub.address, op.address))
      .to.be.true;

    await trader1Sub.connect(trader1).setOperator(op.address, false);

    expect(await context.dealer.isOperatorValid(trader1Sub.address, op.address))
      .to.be.false;
  });

  it("withdraw", async () => {
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("10"),
        utils.parseEther("20"),
        trader1Sub.address
      );
    await checkCredit(context, trader1Sub.address, "10", "20");

    await trader1Sub
      .connect(trader1)
      .requestWithdraw(utils.parseEther("10"), utils.parseEther("20"));
    await trader1Sub.connect(trader1).executeWithdraw(trader1.address, false);
    await checkCredit(context, trader1Sub.address, "0", "0");
    await checkPrimaryAsset(context, trader1.address, "1000000");
    await checkSecondaryAsset(context, trader1.address, "1000000");
  });

  it("trade", async () => {
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("10000"),
        utils.parseEther("0"),
        trader1Sub.address
      );
    await context.dealer
      .connect(trader2)
      .deposit(
        utils.parseEther("10000"),
        utils.parseEther("0"),
        trader2Sub.address
      );
    let o1 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("1").toString(),
      utils.parseEther("-30000").toString(),
      op,
      trader1Sub.address
    );
    let o2 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("-1").toString(),
      utils.parseEther("30000").toString(),
      op,
      trader2Sub.address
    );
    let encodedTradeData = encodeTradeData(
      [o1.order, o2.order],
      [o1.signature, o2.signature],
      [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
    );
    await context.perpList[0].trade(encodedTradeData);

    await checkBalance(context.perpList[0], trader1Sub.address, "1", "-30015");
    await checkBalance(context.perpList[0], trader2Sub.address, "-1", "29997");
    await checkBalance(context.perpList[0], context.ownerAddress, "0", "0");
    await checkCredit(context, context.ownerAddress, "18", "0");
  });

  it("revert cases", async () => {
    await expect(
      trader1Sub.connect(trader2).setOperator(trader2.address, true)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      trader1Sub.connect(trader2).requestWithdraw("10", "10")
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      trader1Sub.connect(trader2).executeWithdraw(trader2.address, false)
    ).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(
      trader1Sub.connect(trader1).init(trader2.address, context.dealer.address)
    ).to.be.revertedWith("ALREADY INITIALIZED");
  });

  it("retrieve asset", async () => {
    await expect(
      trader1.sendTransaction({
        to: trader1Sub.address,
        value: parseEther("0.1"),
        gasLimit: 50000,
      })
    ).reverted;

    await context.primaryAsset.mint([trader1Sub.address], [parseEther("1")]);
    await expect(trader1Sub.retrieve(
      trader1.address,
      context.primaryAsset.address,
      parseEther("1")
    )).to.be.revertedWith("Ownable: caller is not the owner");
    await trader1Sub.connect(trader1).retrieve(
      trader1.address,
      context.primaryAsset.address,
      parseEther("1")
    );
    const balance = await context.primaryAsset.balanceOf(trader1.address)
    expect(balance).to.equal(parseEther("1000001"))
  });
});
