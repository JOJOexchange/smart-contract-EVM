/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;

interface ISubaccount {
    /// @notice return true if the operator isauthorized
    function isValidPerpetualOperator(address operator) external returns (bool);
}
