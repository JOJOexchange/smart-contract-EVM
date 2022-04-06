import { ethers } from "hardhat";
import { BigNumber } from "bignumber.js";
import { Contract, Wallet, utils } from "ethers";
import { Context } from "./context";

let ORDER_STRUCTURE = [
  { name: "perp", type: "address" },
  { name: "signer", type: "address" },
  { name: "orderSender", type: "address" },
  { name: "paperAmount", type: "int128" },
  { name: "creditAmount", type: "int128" },
  { name: "info", type: "bytes32" },
];

export interface Order {
  perp: string;
  signer: string;
  orderSender: string;
  paperAmount: string;
  creditAmount: string;
  info: string;
}

export interface OrderEnv {
  makerFeeRate: string;
  takerFeeRate: string;
  orderSender: string;
  dealerAddress: string;
  EIP712domain: string;
}

export async function getDefaultOrderEnv(dealer: Contract): Promise<OrderEnv> {
  let dealerOwner = await dealer.owner();
  let domain = (await dealer.state()).domainSeparator;
  return {
    makerFeeRate: utils.parseEther("0.0001").toString(),
    takerFeeRate: utils.parseEther("0.0005").toString(),
    orderSender: dealerOwner,
    dealerAddress: dealer.address,
    EIP712domain: domain,
  };
}

export async function buildOrder(
  orderEnv: OrderEnv,
  perpAddress: string,
  paperAmount: string,
  creditAmount: string,
  signer: Wallet,
  subaccount?: string
): Promise<{ order: Order; hash: string; signature: string }> {
  let chainid = await signer.getChainId();
  let domain = {
    name: "JOJO",
    version: "1",
    chainId: chainid,
    verifyingContract: orderEnv.dealerAddress,
  };

  const infoBytes = ethers.utils.solidityPack(
    ["int64", "int64", "uint64", "uint64"],
    [
      orderEnv.makerFeeRate,
      orderEnv.takerFeeRate,
      Math.floor(new Date().getTime() / 1000 + 1000).toFixed(0),
      Math.round(new Date().getTime() / 1000) + "",
    ]
  );

  let order: Order = {
    perp: perpAddress,
    signer: signer.address,
    orderSender: orderEnv.orderSender,
    paperAmount: paperAmount,
    creditAmount: creditAmount,
    info: infoBytes,
  };
  if (subaccount) {
    order.signer = subaccount;
  }
  let types = {
    Order: ORDER_STRUCTURE,
  };

  // console.log("struct", utils._TypedDataEncoder.from(types).hash(order))

  const hash = ethers.utils._TypedDataEncoder.hash(domain, types, order);
  const signature = await signer._signTypedData(domain, types, order);

  return { order: order, hash: hash, signature: signature };
}

export function encodeTradeData(
  orderList: Order[],
  signatureList: string[],
  matchAmountList: string[]
): string {
  let abiCoder = new ethers.utils.AbiCoder();
  return abiCoder.encode(
    [
      "tuple(address perp, address signer, address orderSender, int128 paperAmount, int128 creditAmount, bytes32 info)[]",
      "bytes[]",
      "uint256[]",
    ],
    [orderList, signatureList, matchAmountList]
  );
}

export async function openPosition(
  taker: Wallet,
  maker: Wallet,
  takerPaper: string,
  price: string,
  perp: Contract,
  orderEnv: OrderEnv
) {
  let paperAmount = utils.parseEther(takerPaper);
  let creditAmount = paperAmount.mul(price).mul(-1);
  let o1 = await buildOrder(
    orderEnv,
    perp.address,
    paperAmount.toString(),
    creditAmount.toString(),
    taker
  );
  let o2 = await buildOrder(
    orderEnv,
    perp.address,
    paperAmount.mul(-1).toString(),
    creditAmount.mul(-1).toString(),
    maker
  );

  let encodedTradeData = encodeTradeData(
    [o1.order, o2.order],
    [o1.signature, o2.signature],
    [paperAmount.abs().toString(), paperAmount.abs().toString()]
  );
  await perp.trade(encodedTradeData);
}
