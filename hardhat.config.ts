require("dotenv").config();
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import "@nomicfoundation/hardhat-chai-matchers";
import "solidity-coverage"
module.exports = {
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
    },
    bsc: {
      chainId: 56,
      url: process.env.BSC_URL,
    },
    bsctest: {
      chainId: 97,
      url: process.env.BSCTEST_URL,
    },
    // arbitrumtest: {
    //   chainId: 421613,
    //   url: process.env.ARBITRUMTEST_URL,
    //   account: [process.env.JOJO_LIQUIDATE_PK],
    //   gas: 2100000,
    //   gasPrice: 8000000000,
    //   allowUnlimitedContractSize: true
    // },
    arbitrum: {
      chainId: 42161,
      url: process.env.ARBITRUM_URL,
      account: [process.env.JOJO_MAINNET_DEPLOYER_PK],
      gas: 2100000,
      gasPrice: 10000000000,
      allowUnlimitedContractSize: true
    }
  },
  etherscan: {
    apiKey: {
      bsc: process.env.BSCSCAN_API_KEY,
      bsctest: process.env.BSCSCAN_API_KEY,
      arbirtumtest: process.env.ARBITRUMTEST_API_KEY,
      arbirtum: process.env.ARBITRUMTEST_API_KEY
    },
    customChains: [
      {
        network: "bsc",
        chainId: 56,
        urls: {
          browserURL: process.env.BSC_URL,
          apiURL: process.env.BSC_URL,
        },
      },
      {
        network: "bsctest",
        chainId: 97,
        urls: {
          browserURL: process.env.BSCTEST_URL,
          apiURL: process.env.BSCTEST_URL,
        },
      },
      {
        network: "arbirtumtest",
        chainId: 421613,
        urls: {
          browserURL: process.env.ARBITRUMTEST_URL,
          apiURL: process.env.ARBITRUMTEST_URL,
        },
      },
      {
        network: "arbirtum",
        chainId: 42161,
        urls: {
          browserURL: process.env.ARBITRUM_URL,
          apiURL: process.env.ARBITRUM_URL,
        },
      },
    ],
  },
  gasReporter: {
    enabled: false,
  },
};