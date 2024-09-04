// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/oracle/ChainlinkDS.sol";
import "./Utils.s.sol";

contract ChainlinkDSPortalScript is Script {
    // add this to be excluded from coverage report
    function test() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address _dsVerifyProxy = 0xDE1A28D87Afd0f546505B28AB50410A5c3a7387a;
        uint256 _usdcHeartbeat = 86400;
        address _usdcSource = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
        address _reportSubmitter = 0x58D6e7ACcC617758F890Ba796d34777d2c46210C;
        address _feeTokenAddress = 0x4200000000000000000000000000000000000006;

        ChainlinkDSPortal chainlinkDSPortal = new ChainlinkDSPortal(
            _dsVerifyProxy,
            _reportSubmitter,
            _usdcHeartbeat,
            _usdcSource,
            _feeTokenAddress
        );
        
        vm.stopBroadcast();

        // 自动执行验证
        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(_dsVerifyProxy,_reportSubmitter,_usdcHeartbeat,_usdcSource,_feeTokenAddress);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(chainlinkDSPortal));
        inputs[3] = "src/oracle/ChainlinkDS.sol:ChainlinkDSPortal";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }

contract ChainlinkDSPortalScriptBaseTestnet is Script {
    // add this to be excluded from coverage report
    function test() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address _dsVerifyProxy = 0x8Ac491b7c118a0cdcF048e0f707247fD8C9575f9;
        uint256 _usdcHeartbeat = 86400;
        address _usdcSource = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
        address _reportSubmitter = 0x1cA8dd11fF12Fc22cd2ab83317cFd90df6a73694;
        address _feeTokenAddress = 0x4200000000000000000000000000000000000006;// address _owner = 0x1cA8dd11fF12Fc22cd2ab83317cFd90df6a73694;

        ChainlinkDSPortal chainlinkDSPortal = new ChainlinkDSPortal(
            _dsVerifyProxy,
            _reportSubmitter,
            _usdcHeartbeat,
            _usdcSource,
            _feeTokenAddress
        );

        chainlinkDSPortal.newPriceSourceConfig(
            "BTCUSDC",
            0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298,
            0x00037da06d56d083fe599397a4769a042d63aa73dc4ef57709d31e9971a5b439,
            20,
            30,
            86400
        );
        chainlinkDSPortal.newPriceSourceConfig(
            "ETHUSDC",
            0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            0x000359843a543ee2fe414dc14c7e7920ef10f4372990b79d6361cdc0dd1ba782,
            20,
            30,
            86400
        );
        // chainlinkDSPortal.transferOwnership(_owner);
        vm.stopBroadcast();

        // 自动执行验证
        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(_dsVerifyProxy,_reportSubmitter,_usdcHeartbeat,_usdcSource,_feeTokenAddress);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(chainlinkDSPortal));
        inputs[3] = "src/oracle/ChainlinkDS.sol:ChainlinkDSPortal";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}
