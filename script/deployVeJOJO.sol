// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/token/veJOJO.sol";
import "./utils.s.sol";

contract DeployVeJOJOMainnet is Script {
    // add this to be excluded from coverage report
    function test() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署 veJOJO
        address jojoToken = 0x0645bC5cDff2376089323Ac20Df4119e48e4BCc4; // JOJO token 地址
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // usdc token 地址
        address owner = 0xD0cFCf1899A749bf0398fc885DB7ee0479C05eFC;  // owner 地址
        
        veJOJO v = new veJOJO(
            jojoToken,    // JOJO token
            usdc
        );
        
        v.transferOwnership(owner);
        vm.stopBroadcast();

        // 验证合约
        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(
            jojoToken,
            usdc
        );
        
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(v));
        inputs[3] = "src/token/veJOJO.sol:veJOJO";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}

contract DeployVeJOJOTest is Script {
    // add this to be excluded from coverage report
    function test() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署 veJOJO
        address jojoToken = 0xA42589C591f8AE08B0e2C2C18439d72628a66c3E; // JOJO token 地址
        address usdc = 0x7107B28375Fa4cc1deaAad58F2f0B5F1d921f3DE; // usdc token 地址
        address owner = 0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B;  // owner 地址
        
        veJOJO v = new veJOJO(
            jojoToken,    // JOJO token
            usdc
        );
        
        v.transferOwnership(owner);
        vm.stopBroadcast();

        // 验证合约
        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(
            jojoToken,
            usdc
        );
        
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(v));
        inputs[3] = "src/token/veJOJO.sol:veJOJO";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}