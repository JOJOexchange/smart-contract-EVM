/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "./libraries/SignedDecimalMath.sol";
import "./JUSDBank.sol";

/// @notice User's multi-step operation on the JUSDBank like: deposit and borrow
contract JUSDMulticall {
    using SignedDecimalMath for uint256;

    function multiCall(bytes[] memory callData) external returns (bytes[] memory returnData) {
        returnData = new bytes[](callData.length);

        for (uint256 i; i < callData.length; i++) {
            (bool success, bytes memory res) = address(this).delegatecall(callData[i]);
            if (success == false) {
                assembly {
                    let ptr := mload(0x40)
                    let size := returndatasize()
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            }
            returnData[i] = res;
        }
    }

    // Helper

    function getMulticallData(bytes[] memory callData) external pure returns (bytes memory) {
        return abi.encodeWithSignature("multiCall(bytes[])", callData);
    }

    function getDepositData(
        address from,
        address collateral,
        uint256 amount,
        address to
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("deposit(address,address,uint256,address)", from, collateral, amount, to);
    }

    function getBorrowData(uint256 amount, address to, bool isDepositToJOJO) external pure returns (bytes memory) {
        return abi.encodeWithSignature("borrow(uint256,address,bool)", amount, to, isDepositToJOJO);
    }

    function getRepayData(uint256 amount, address to) external pure returns (bytes memory) {
        return abi.encodeWithSignature("repay(uint256,address)", amount, to);
    }

    function getSetOperator(address operator, bool isValid) external pure returns (bytes memory) {
        return abi.encodeWithSignature("setOperator(address,bool)", operator, isValid);
    }

    function getWithdrawData(
        address collateral,
        uint256 amount,
        address to,
        bool isInternal
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("withdraw(address,uint256,address,bool)", collateral, amount, to, isInternal);
    }
}
