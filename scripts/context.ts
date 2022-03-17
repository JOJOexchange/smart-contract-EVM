import { ethers } from "hardhat";
import { Contract, Signer, utils } from "ethers";

/*
    Default Context Params
    10 characters: owner insurance trader1~8
    3 perp markets:
    - BTC 20x 3% liquidation 1% price offset 1% insurance
    - ETH 10x 5% liquidation 1% price offset 1% insurance
    - AR  5x  10% liquidation 3% price offset 2% insurance
*/

export interface Context {
  underlyingAsset: Contract;
  dealer: Contract;
  perpList: Contract[];
  priceSourceList: Contract[];
  owner: Signer;
  ownerAddress: string;
  insurance: Signer;
  insuranceAddress: string;
  traderList: Signer[];
  traderAddressList: string[];
}

export async function basicContext(): Promise<Context> {
  let signers: Signer[] = await ethers.getSigners();

  let underlyingAsset: Contract = await (
    await ethers.getContractFactory("TestERC20")
  ).deploy("USDT", "USDT");
  let jojoOrder: Contract = await (
    await ethers.getContractFactory("JOJOOrder")
  ).deploy();
  let dealer = await (
    await ethers.getContractFactory("JOJODealer")
  ).deploy(
    underlyingAsset.address,
    jojoOrder.address
  );
  await dealer.setInsurance(await signers[1].getAddress())

  let perpList: Contract[] = [];
  let priceSourceList: Contract[] = [];
  for (let index = 0; index < 3; index++) {
    perpList[index] = await (
      await ethers.getContractFactory("Perpetual")
    ).deploy(dealer.address);
    priceSourceList[index] = await (
      await ethers.getContractFactory("TestMarkPriceSource")
    ).deploy();
    await dealer.registerNewPerp(perpList[index].address, [
      100,
      100,
      100,
      100,
      priceSourceList[index].address,
    ]);
  }

  let traderList: Signer[] = [];
  let traderAddressList: string[] = [];
  for (let index = 2; index < 10; index++) {
    let trader = signers[index];
    let traderAddress = await signers[index].getAddress();
    traderList.push(trader);
    traderAddressList.push(traderAddress);
    await underlyingAsset
      .connect(signers[index])
      .approve(dealer.address, utils.parseEther("1000000"));
    await underlyingAsset.mint([traderAddress], [utils.parseEther("1000000")]);
  }

  return {
    underlyingAsset: underlyingAsset,
    dealer: dealer,
    perpList: perpList,
    priceSourceList: priceSourceList,
    owner: signers[0],
    ownerAddress: await signers[0].getAddress(),
    insurance: signers[1],
    insuranceAddress: await signers[1].getAddress(),
    traderList: signers.slice(2, 10),
    traderAddressList: traderAddressList,
  };
}
