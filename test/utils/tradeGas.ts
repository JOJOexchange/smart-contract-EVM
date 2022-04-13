import "./hooks";
import { Wallet, utils } from "ethers";
import { basicContext, Context } from "../../scripts/context";
import {
  buildOrder,
  encodeTradeData,
  getDefaultOrderEnv,
  openPosition,
  OrderEnv,
} from "../../scripts/order";

/*
    gas1 = 2 order 2 trader
    gas2 = 3 order 2 trader
    gas3 = 3 order 3 trader

    gas2-gas1 = order gas cost
    gas3-gas1 = trader gas cost
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
    trader3 = context.traderList[2];
    await context.dealer
      .connect(trader1)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader1.address
      );
    await context.dealer
      .connect(trader2)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader2.address
      );
    await context.dealer
      .connect(trader3)
      .deposit(
        utils.parseEther("0"),
        utils.parseEther("1000000"),
        trader3.address
      );
    orderEnv = await getDefaultOrderEnv(context.dealer);
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
      trader3,
      "2",
      "30000",
      context.perpList[0],
      orderEnv
    );
  });

  it("gas calculate", async () => {
    let o1 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("10").toString(),
      utils.parseEther("-300000").toString(),
      trader1
    );
    let o2_1 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("-10").toString(),
      utils.parseEther("300000").toString(),
      trader2
    );
    let o2_2 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("-5").toString(),
      utils.parseEther("150000").toString(),
      trader2
    );
    let o3 = await buildOrder(
      orderEnv,
      context.perpList[0].address,
      utils.parseEther("-10").toString(),
      utils.parseEther("300000").toString(),
      trader3
    );
    let data1 = encodeTradeData(
      [o1.order, o2_1.order],
      [o1.signature, o2_1.signature],
      [utils.parseEther("1").toString(), utils.parseEther("1").toString()]
    );
    let data2 = encodeTradeData(
      [o1.order, o2_1.order, o2_2.order],
      [o1.signature, o2_1.signature, o2_2.signature],
      [
        utils.parseEther("2").toString(),
        utils.parseEther("1").toString(),
        utils.parseEther("1").toString(),
      ]
    );
    let data3 = encodeTradeData(
      [o1.order, o2_1.order, o3.order],
      [o1.signature, o2_1.signature, o3.signature],
      [
        utils.parseEther("2").toString(),
        utils.parseEther("1").toString(),
        utils.parseEther("1").toString(),
      ]
    );
    const gas1 = (await (await context.perpList[0].trade(data1)).wait())
      .gasUsed;
    const gas2 = (await (await context.perpList[0].trade(data2)).wait())
      .gasUsed;
    const gas3 = (await (await context.perpList[0].trade(data3)).wait())
      .gasUsed;
    console.log("gas1:", gas1.toString());
    console.log("gas2:", gas2.toString());
    console.log("gas3:", gas3.toString());
    console.log("order gas:", gas2.sub(gas1).toString());
    console.log("maker gas:", gas3.sub(gas1).toString());
  });
});
