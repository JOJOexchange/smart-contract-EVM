import { ethers } from "hardhat";

export async function timeJump(
  secondes:number
) {
  await ethers.provider.send("evm_increaseTime", [secondes])
}