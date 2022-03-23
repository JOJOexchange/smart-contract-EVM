import { ethers } from "hardhat";
import { Contract, Wallet, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";
import {
  buildOrder,
  encodeTradeData,
  getDefaultOrderEnv,
  openPosition,
  OrderEnv,
} from "../scripts/order";

/*
  Test cases list
  - single match 
    - taker long
    - taker short
    - close position
  - multi match
    - maker de-duplicate
    - without maker de-duplicate
  - using maker price
  - negative fee rate
    - independent order fee rate
  - change funding ratio

  Revert cases list
  - order price negative
  - order amount 0
  - wrong signer
  - wrong sender
  - wrong perp
  - wrong match amount
  - be liquidated
  - order over filled
  - price not match
  - 
*/

describe("Trade", () => {
  let context: Context;
  let trader1: Wallet;
  let trader2: Wallet;
  let trader3: Wallet;
  let orderEnv: OrderEnv;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    trader3 = context.traderList[1];
    await context.dealer.setVirtualCredit(
      trader1.address,
      utils.parseEther("1000000")
    );
    await context.dealer.setVirtualCredit(
      trader2.address,
      utils.parseEther("1000000")
    );
    await context.dealer.setVirtualCredit(
      trader3.address,
      utils.parseEther("1000000")
    );
    orderEnv = await getDefaultOrderEnv(context.dealer);
  });

  it("match single order", async () => {
    await openPosition(
      trader1,
      trader2,
      "1",
      "30000",
      context.perpList[0],
      orderEnv
    )
    console.log(await context.perpList[0].balanceOf(trader1.address),trader1.address)
    console.log(await context.perpList[0].balanceOf(trader2.address),trader2.address)
    console.log(await context.perpList[0].balanceOf(context.ownerAddress),context.ownerAddress)
  });

  //   it('Assigns initial balance', async () => {
  //       const gretter = await ethers.getContractFactory("")
  //     expect(await token.balanceOf(wallet.address)).to.equal(1000);
  //   });

  //   it('Transfer adds amount to destination account', async () => {
  //     await token.transfer(walletTo.address, 7);
  //     expect(await token.balanceOf(walletTo.address)).to.equal(7);
  //   });

  //   it('Transfer emits event', async () => {
  //     await expect(token.transfer(walletTo.address, 7))
  //       .to.emit(token, 'Transfer')
  //       .withArgs(wallet.address, walletTo.address, 7);
  //   });

  //   it('Can not transfer above the amount', async () => {
  //     await expect(token.transfer(walletTo.address, 1007)).to.be.reverted;
  //   });

  //   it('Can not transfer from empty account', async () => {
  //     const tokenFromOtherWallet = token.connect(walletTo);
  //     await expect(tokenFromOtherWallet.transfer(wallet.address, 1))
  //       .to.be.reverted;
  //   });

  //   it('Calls totalSupply on BasicToken contract', async () => {
  //     await token.totalSupply();
  //     expect('totalSupply').to.be.calledOnContract(token);
  //   });

  //   it('Calls balanceOf with sender address on BasicToken contract', async () => {
  //     await token.balanceOf(wallet.address);
  //     expect('balanceOf').to.be.calledOnContractWith(token, [wallet.address]);
  //   });
});
