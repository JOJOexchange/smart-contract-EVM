/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.12",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};
