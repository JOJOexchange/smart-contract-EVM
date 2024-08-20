// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/oracle/ChainlinkDS.sol";

contract ChainlinkDSPortalScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        ChainlinkDSPortal chainlinkDSPortal = new ChainlinkDSPortal(
        // address _dsVerifyProxy
            0xDE1A28D87Afd0f546505B28AB50410A5c3a7387a,
        // uint256 _usdcHeartbeat (in second)
            86400,
        // address _usdcSource
            0x7e860098F58bBFC8648a4311b374B1D669a2bc6B
        );
        vm.stopBroadcast();

        // 自动执行验证
        string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        string[] memory inputs = new string[](6);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = addressToString(address(chainlinkDSPortal));
        inputs[3] = "src/oracle/ChainlinkDS.sol:ChainlinkDSPortal";
        inputs[4] = "--etherscan-api-key";
        inputs[5] = etherscanApiKey;

        bytes memory res = vm.ffi(inputs);
        console.log(string(res));
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}

contract ChainlinkDSPortalScriptTestnet is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        new ChainlinkDSPortal(
        // address _dsVerifyProxy
            0x8Ac491b7c118a0cdcF048e0f707247fD8C9575f9,
        // uint256 _usdcHeartbeat (in second)
            86400,
        // address _usdcSource
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        );
        vm.stopBroadcast();

        // 自动执行验证
        // string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        // string[] memory inputs = new string[](6);
        // inputs[0] = "forge";
        // inputs[1] = "verify-contract";
        // inputs[2] = addressToString(address(chainlinkDSPortal));
        // inputs[3] = "src/oracle/ChainlinkDS.sol:ChainlinkDSPortal";
        // inputs[4] = "--etherscan-api-key";
        // inputs[5] = etherscanApiKey;

        // bytes memory res = vm.ffi(inputs);
        // console.log(string(res));
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}