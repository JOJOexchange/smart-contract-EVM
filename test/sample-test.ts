import {ethers} from "hardhat"
import {Contract, Signer} from "ethers"
import {expect} from "chai"

describe('BasicToken', () => {
    let accounts: Signer[]
    let token: Contract

  beforeEach(async () => {
    accounts = await ethers.getSigners()
    token = await (await ethers.getContractFactory("TestERC20")).deploy("USDT", "USDT")
  });

  it('mint', async()=>{
      let address1 = await accounts[0].getAddress()
      let address2 = await accounts[1].getAddress()
      await token.mint([address1, address2],[1000,2000])
      console.log(await token.balanceOf(address1))
      expect(await token.balanceOf(address1)).to.equal(1000)
      console.log(await token.balanceOf(address2))
      expect(await token.balanceOf(address2)).to.equal(2000)
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