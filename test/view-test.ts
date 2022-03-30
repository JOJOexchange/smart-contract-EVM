// await openPosition(
//     trader1,
//     trader2,
//     "1",
//     "30000",
//     context.perpList[0],
//     orderEnv
//   );

  // trader1 long
  // exposure = 0 netValue = -15+10000-30000 = -20015
  // temp1 = 20015
  // temp2 = 0.97
  // liqPrice = 20015/0.97 = 20634.020618556701030927

  // trader2 short
  // exposure = 0 netValue = -3+10000+30000 = 39997
  // temp1 = -39997
  // temp2 = 1.03
  // liqPrice = 39997/1.03 = 38832.038834951456310679

  // console.log(
  //   await context.dealer.getLiquidationPrice(
  //     trader1.address,
  //     context.perpList[0].address
  //   )
  // );
  // console.log(
  //   await context.dealer.getLiquidationPrice(
  //     trader2.address,
  //     context.perpList[0].address
  //   )
  // );



//   it.only("multi position check", async () => {
//     await openPosition(
//       trader1,
//       trader2,
//       "1",
//       "30000",
//       context.perpList[0],
//       orderEnv
//     );
//     await openPosition(
//       trader1,
//       trader2,
//       "10",
//       "2000",
//       context.perpList[1],
//       orderEnv
//     );
//     await context.priceSourceList[0].setMarkPrice(utils.parseEther("21262"));
//     expect(await context.dealer.isSafe(trader1.address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[1].address)).to.be.false;
//     expect(await context.dealer.isSafe(trader2.address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[1].address)).to.be.true;

//     await context.priceSourceList[0].setMarkPrice(utils.parseEther("38248"))
//     expect(await context.dealer.isSafe(trader1.address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[1].address)).to.be.true;
//     expect(await context.dealer.isSafe(trader2.address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[1].address)).to.be.false;

//     await context.priceSourceList[0].setMarkPrice(utils.parseEther("30000"))

//     await context.priceSourceList[1].setMarkPrice(utils.parseEther("1213"))
//     expect(await context.dealer.isSafe(trader1.address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[1].address)).to.be.false;
//     expect(await context.dealer.isSafe(trader2.address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[1].address)).to.be.true;

//     await context.priceSourceList[1].setMarkPrice(utils.parseEther("2714"))
//     expect(await context.dealer.isSafe(trader1.address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader1.address, context.perpList[1].address)).to.be.true;
//     expect(await context.dealer.isSafe(trader2.address)).to.be.false;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[0].address)).to.be.true;
//     expect(await context.dealer.isPositionSafe(trader2.address, context.perpList[1].address)).to.be.false;

//     console.log(
//       await context.dealer.getLiquidationPrice(
//         trader1.address,
//         context.perpList[0].address
//       )
//     );
//     console.log(
//       await context.dealer.getLiquidationPrice(
//         trader1.address,
//         context.perpList[1].address
//       )
//     );
//     console.log(
//       await context.dealer.getLiquidationPrice(
//         trader2.address,
//         context.perpList[0].address
//       )
//     );
//     console.log(
//       await context.dealer.getLiquidationPrice(
//         trader2.address,
//         context.perpList[1].address
//       )
//     );
//   });
// });

// 21262886597938144329896
// 1213157894736842105263
// 38247572815533980582524
// 2713809523809523809523