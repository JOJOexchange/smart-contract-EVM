require("dotenv").config();
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "solidity-coverage";
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-etherscan";

export default {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100000,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
      gas: 20000000,
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    enabled: false,
  },
};