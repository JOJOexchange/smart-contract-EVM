// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/token/MerkleDistributorWithDeadline.sol";
import "./utils.s.sol";

contract DeployMerkleDistributor is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address owner = 0xD0cFCf1899A749bf0398fc885DB7ee0479C05eFC;
        address token = 0x0645bC5cDff2376089323Ac20Df4119e48e4BCc4;
        bytes32 root = 0x86a94d64a9d8c155e59669d37e614a788e7d304cb96c943d3b46cfd2cb8a89f7;
        uint256 endTime = 1734188400;
        MerkleDistributorWithDeadline distributor = new MerkleDistributorWithDeadline(
            // token
            token,
            // root
            root,
            // timestamp
            endTime
        );
        distributor.transferOwnership(owner);
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(token,root,endTime);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(distributor));
        inputs[3] = "src/token/MerkleDistributorWithDeadline.sol:MerkleDistributorWithDeadline";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}

contract DeployMerkleDistributorTest is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address token = 0xA42589C591f8AE08B0e2C2C18439d72628a66c3E;
        bytes32 root = 0x96a180650761c384ed626edc85938b9af8f437fc9eaaa42fd1b508623b844099;
        uint256 endTime = 1827740800;
        MerkleDistributorWithDeadline distributor = new MerkleDistributorWithDeadline(
            // token
            token,
            // root
            root,
            // timestamp
            endTime
        );
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(token,root,endTime);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(distributor));
        inputs[3] = "src/token/MerkleDistributorWithDeadline.sol:MerkleDistributorWithDeadline";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}
