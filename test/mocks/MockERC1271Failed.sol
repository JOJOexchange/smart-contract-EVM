/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

contract MockERC1271Failed {
    // add this to be excluded from coverage report
    function test() public { }

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return 0x1626ba72;
    }
}
