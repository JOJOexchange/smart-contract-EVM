// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../lib/forge-std/src/Script.sol";
import "../src/fundingRateLimiter/FundingRateUpdateLimiterZK.sol";
import "./utils.s.sol";

contract FundingRateUpdateLimiterZKScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        // Testnet
        address _dealer = 0x65bE09345311aCc72d9358Ea7d7B13A91DFF51B6;
        uint8 _speedMultiplier = 3;
        address _brevisProof = 0x9Bb46D5100d2Db4608112026951c9C965b233f4D;
        address _owner = 0xF1D7Ac5Fd1b806d24bCd2764C7c29A9fAd51698B;
        bytes32 _vkHash = 0x289682858ff8c014eb45e19b4275de16f705ca841dcaccc0583bd8dc7fd76745;

        FundingRateUpdateLimiterZK limiter = new FundingRateUpdateLimiterZK(
            _dealer,
            _speedMultiplier,
            _brevisProof
        );
        limiter.setVkHash(_vkHash);
        limiter.transferOwnership(_owner);
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(_dealer,_speedMultiplier,_brevisProof);
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(limiter));
        inputs[3] = "src/fundingRateLimiter/FundingRateUpdateLimiterZK.sol:FundingRateUpdateLimiterZK";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}
