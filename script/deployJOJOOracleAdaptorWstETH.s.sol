// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "forge-std/Script.sol";
// import "../src/oracle/JOJOOracleAdaptorWstETH.sol";
// import "forge-std/Test.sol";

// contract JOJOOracleAdaptorWstETHScript is Script {
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("JOJO_ARBITRUM_MAINNET_DEPLOYER_PK");
//         vm.startBroadcast(deployerPrivateKey);
//         new JOJOOracleAdaptorWstETH(
//             // source
//             0xb523AE262D20A936BC152e6023996e46FDC2A95D,
//             // decimalCorrection
//             20,
//             //heartbeatInterval
//                 86400,
//             // usdc
//                 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,
//             //_USDCHeartbeat
//             86400,
//             //_ETHSource
//                 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,
//             //ETHHeartbeat
//                 86400
//         );
//         console2.log("deploy JOJOOracleAdaptor");
//         vm.stopBroadcast();
//     }
// }
