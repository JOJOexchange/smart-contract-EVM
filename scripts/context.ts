import { ethers } from "hardhat";
import { Contract, Wallet, Signer, utils } from "ethers";

/*
    Default Context Params
    5 characters: owner insurance trader1~3
    3 perp markets:
    - BTC 20x 
      3% liquidation 1% price offset 1% insurance 
    - ETH 10x 
      5% liquidation 1% price offset 1% insurance 
    - AR  5x  
      10% liquidation 3% price offset 2% insurance 
    Init price
    - BTC 30000
    - ETH 2000
    - AR 10
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
  traderList: Wallet[];
}

export async function basicContext(): Promise<Context> {

   let owner = (await ethers.getSigners())[0]
   let ownerAddress = await owner.getAddress()

   let insurance = (await ethers.getSigners())[1]
   let insuranceAddress = await insurance.getAddress()

  let traders: Wallet[] = [];
  for (let i = 0; i < 3; i++) {
    let wallet = new ethers.Wallet(
      "0x012345678901234567890123456789012345678901234567890123456789012"+i.toString(),
      ethers.provider
    );
    traders.push(wallet);
    let tx = {
        to: wallet.address,
        value:utils.parseEther("10")
    }
    await owner.sendTransaction(tx)
  }

  // Deploy libraries
  const EIP712Lib = await (await ethers.getContractFactory("EIP712")).deploy();
  const LiquidationLib = await (
    await ethers.getContractFactory("Liquidation")
  ).deploy();
  const FundingLib = await (
    await ethers.getContractFactory("Funding", {
      libraries: { Liquidation: LiquidationLib.address },
    })
  ).deploy();
  const TradingLib = await (
    await ethers.getContractFactory("Trading", {
      libraries: {
        EIP712: EIP712Lib.address,
        Liquidation: LiquidationLib.address,
      },
    })
  ).deploy();

  // deploy core contracts
  let underlyingAsset: Contract = await (
    await ethers.getContractFactory("TestERC20")
  ).deploy("USDT", "USDT");
  let dealer = await (
    await ethers.getContractFactory("JOJODealer", {
      libraries: {
        EIP712: EIP712Lib.address,
        Funding: FundingLib.address,
        Liquidation: LiquidationLib.address,
        Trading: TradingLib.address,
      },
    })
  ).deploy(underlyingAsset.address);
  await dealer.setInsurance(insuranceAddress);

  let perpList: Contract[] = [];
  let priceSourceList: Contract[] = [];
  for (let index = 0; index < 3; index++) {
    perpList[index] = await (
      await ethers.getContractFactory("Perpetual")
    ).deploy(dealer.address);
    priceSourceList[index] = await (
      await ethers.getContractFactory("TestMarkPriceSource")
    ).deploy();
  }

  // set BTC market
  await dealer.setPerpRiskParams(perpList[0].address, [
    utils.parseEther("0.03"), // 3% liquidation
    utils.parseEther("0.01"), // 1% price offset
    // utils.parseEther("100"), // 100BTC max
    utils.parseEther("0.01"), // 1% insurance fee
    utils.parseEther("1"), // init funding ratio 1
    priceSourceList[0].address, // mark price source
    "BTC20x", // name
    true, // register
  ]);
  await priceSourceList[0].setMarkPrice(utils.parseEther("30000"));

  // set ETH market
  await dealer.setPerpRiskParams(perpList[1].address, [
    utils.parseEther("0.05"), // 5% liquidation
    utils.parseEther("0.01"), // 1% price offset
    // utils.parseEther("1000"), // 1000ETH max
    utils.parseEther("0.01"), // 1% insurance fee
    utils.parseEther("1"), // init funding ratio 1
    priceSourceList[1].address, // mark price source
    "ETH10x", // name
    true, // register
  ]);
  await priceSourceList[1].setMarkPrice(utils.parseEther("2000"));

  // set AR market
  await dealer.setPerpRiskParams(perpList[2].address, [
    utils.parseEther("0.10"), // 10% liquidation
    utils.parseEther("0.03"), // 3% price offset
    // utils.parseEther("1000"), // 1000AR max
    utils.parseEther("0.02"), // 2% insurance fee
    utils.parseEther("1"), // init funding ratio 1
    priceSourceList[2].address, // mark price source
    "AR5x", // name
    true, // register
  ]);
  await priceSourceList[2].setMarkPrice(utils.parseEther("10"));

  for (let index = 0; index < traders.length; index++) {
    let trader = traders[index];
    // 1M for each trader
    await underlyingAsset
      .connect(trader)
      .approve(dealer.address, utils.parseEther("1000000"));
    await underlyingAsset.mint([trader.address], [utils.parseEther("1000000")]);
  }

  return {
    underlyingAsset: underlyingAsset,
    dealer: dealer,
    perpList: perpList,
    priceSourceList: priceSourceList,
    owner: owner,
    ownerAddress: ownerAddress,
    insurance: insurance,
    insuranceAddress: insuranceAddress,
    traderList: traders,
  };
}
