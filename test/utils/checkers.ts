import { Contract, utils } from "ethers";
import { expect } from "chai";
import { Context } from "../../scripts/context";

export async function checkCredit(
  context: Context,
  trader: string,
  primaryCredit: string,
  secondaryCredit: string
) {
  const credit = await context.dealer.getCreditOf(trader);
  expect(credit.primaryCredit).to.equal(utils.parseEther(primaryCredit));
  expect(credit.secondaryCredit).to.equal(utils.parseEther(secondaryCredit));
}

export async function checkBalance(
    perp: Contract,
    trader: string,
    paper:string,
    credit:string
) {
    const balance = await perp.balanceOf(trader)
    expect(balance[0]).to.equal(utils.parseEther(paper));
    expect(balance[1]).to.equal(utils.parseEther(credit))
}

export async function checkPrimaryAsset(
  context: Context,
  account: string,
  expectedBalance: string
) {
  const balance = await context.primaryAsset.balanceOf(account);
  expect(balance).to.equal(utils.parseEther(expectedBalance));
}

export async function checkSecondaryAsset(
  context: Context,
  account: string,
  expectedBalance: string
) {
  const balance = await context.secondaryAsset.balanceOf(account);
  expect(balance).to.equal(utils.parseEther(expectedBalance));
}