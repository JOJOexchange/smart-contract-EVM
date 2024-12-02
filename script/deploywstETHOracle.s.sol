// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/oracle/OracleAdaptorWstETH.sol";
import "./utils.s.sol";

contract OracleAdaptorScript is Script {
    // add this to be excluded from coverage report
    function test() public { }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("JOJO_DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
        
        // wstETH/ETH price source
        address wstETHSource = 0x43a5C292A453A3bF3606fa856197f09D7B74251a;
        // wstETH/ETH heartbeat interval
        uint256 heartbeatInterval = 86_400;
        // USDC price source
        address usdcSource = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
        // USDC heartbeat
        uint256 usdcHeartbeat = 86_400;
        // ETH price source
        address ethSource = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
        // ETH heartbeat
        uint256 ethHeartbeat = 86_400;

        JOJOOracleAdaptorWstETH oracle = new JOJOOracleAdaptorWstETH(
            wstETHSource,
            heartbeatInterval,
            usdcSource,
            usdcHeartbeat,
            ethSource,
            ethHeartbeat
        );
        vm.stopBroadcast();

        string memory chainId = vm.envString("CHAIN_ID");
        bytes memory arguments = abi.encode(
            wstETHSource,
            heartbeatInterval,
            usdcSource,
            usdcHeartbeat,
            ethSource,
            ethHeartbeat
        );
        
        string[] memory inputs = new string[](8);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = Utils.addressToString(address(oracle));
        inputs[3] = "src/oracle/OracleAdaptorWstETH.sol:JOJOOracleAdaptorWstETH";
        inputs[4] = "--chain-id";
        inputs[5] = chainId;
        inputs[6] = "--constructor-args";
        inputs[7] = Utils.bytesToStringWithout0x(arguments);
        Utils.logInputs(inputs);
    }
}
