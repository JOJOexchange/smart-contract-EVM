/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.9",
  settings: {
    optimizer: {
      enabled: true,
      runs: 10000,
    },
  },
};
