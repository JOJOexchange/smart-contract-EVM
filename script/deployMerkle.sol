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
        address token = 0x0645bC5cDff2376089323Ac20Df4119e48e4BCc4;
        bytes32 root = 0x915135dccd7288b4da16541980aa0cb78e5166f48b22029dcf8104dd84c0419a;
        uint256 endTime = 1727740800;
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
