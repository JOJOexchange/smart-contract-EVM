// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/subaccount/BotSubaccountFactory.sol";
import "./utils.s.sol";

contract BotSubaccountFactoryScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address _dealer = 0x2f7c3cF9D9280B165981311B822BecC4E05Fe635;
        address _operator = 0xf7deBaF84774B0E4DA659eDe243c8A84A2aFcD14;
        address botSubaccountFactory = address(new BotSubaccountFactory(_dealer, _operator));
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(_dealer, _operator);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(botSubaccountFactory);
        inputs[3] = "src/subaccount/BotSubaccountFactory.sol:BotSubaccountFactory";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}

contract BotSubaccountFactoryScriptTest is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        address _dealer = 0x65bE09345311aCc72d9358Ea7d7B13A91DFF51B6;
        address _operator = 0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B;
        address botSubaccountFactory = address(new BotSubaccountFactory(_dealer, _operator));
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(_dealer, _operator);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(botSubaccountFactory);
        inputs[3] = "src/subaccount/BotSubaccountFactory.sol:BotSubaccountFactory";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}