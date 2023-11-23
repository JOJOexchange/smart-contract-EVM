/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../intf/IPerpetual.sol";

contract SmartOrderSender is Ownable, ReentrancyGuard {
    
    function bundleTrade(
        address beforeDes,
        bytes calldata beforeCallData,
        address perp,
        bytes calldata tradeData,
        address afterDes,
        bytes calldata afterCallData
    ) external onlyOwner {
        _executeFunctionCall(beforeDes, beforeCallData);
        IPerpetual(perp).trade(tradeData);
        _executeFunctionCall(afterDes, afterCallData);
    }

    function _executeFunctionCall(
        address des,
        bytes calldata callData
    ) private {
        if (des != address(0)) {
            (bool success, bytes memory returnData) = des.call(callData);
            if (!success) {
                if (returnData.length > 0) {
                    string memory errorMessage = abi.decode(
                        returnData,
                        (string)
                    );
                    revert(errorMessage);
                } else {
                    revert("External call failed without error message");
                }
            }
        }
    }
}
