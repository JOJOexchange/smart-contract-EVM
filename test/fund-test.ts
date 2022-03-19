import { ethers } from "hardhat";
import { Contract, Signer, utils } from "ethers";
import { expect } from "chai";
import { basicContext, Context } from "../scripts/context";

describe("Funding", () => {
  let context: Context;
  let trader1: Signer;
  let trader2: Signer;
  let trader1Address: string;
  let trader2Address: string;

  beforeEach(async () => {
    context = await basicContext();
    trader1 = context.traderList[0];
    trader2 = context.traderList[1];
    trader1Address = await trader1.getAddress();
    trader2Address = await trader2.getAddress();
  });

  it("deposit", async () => {
    let c = context.dealer.connect(trader1);
    await c.deposit(utils.parseEther("100000"), trader1Address);
    expect(await context.underlyingAsset.balanceOf(trader1Address)).to.equal(
      utils.parseEther("900000")
    );
    expect(
      await context.underlyingAsset.balanceOf(context.dealer.address)
    ).to.equal(utils.parseEther("100000"));
    const credit = await context.dealer.getCreditOf(trader1Address);
    expect(credit.trueCredit).to.equal(utils.parseEther("100000"));
    expect(credit.virtualCredit).to.equal(utils.parseEther("0"));
  });

  it("set virtual credit", async () => {
    await context.dealer.setVirtualCredit(trader1Address, utils.parseEther("10"))
    await context.dealer.setVirtualCredit(trader2Address, utils.parseEther("20"))
    const credit1 = await context.dealer.getCreditOf(trader1Address);
    expect(credit1.trueCredit).to.equal(utils.parseEther("0"));
    expect(credit1.virtualCredit).to.equal(utils.parseEther("10"));
    const credit2 = await context.dealer.getCreditOf(trader2Address);
    expect(credit2.trueCredit).to.equal(utils.parseEther("0"));
    expect(credit2.virtualCredit).to.equal(utils.parseEther("20"));
  })

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
