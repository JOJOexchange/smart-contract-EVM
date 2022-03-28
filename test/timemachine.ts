import { ethers } from "hardhat";

export function sleep(ms: number) {
    return new Promise( resolve => setTimeout(resolve, ms) );
}

export async function timeJump(
  secondes:number
) {
  await ethers.provider.send("evm_increaseTime", [secondes])
  await sleep(50)
  await ethers.provider.send("evm_mine",[])
}