/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice ERC20Token JOJO

contract JOJO is Ownable, ERC20 {
    
    constructor(address to) ERC20("JOJO", "JOJO") {
        _mint(to, 100_000_000 * 10 ** 18);
    }
}
