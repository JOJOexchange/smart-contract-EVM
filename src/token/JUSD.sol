/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice ERC20Token JUSD
// JUSD is the secondary asset. Users deposit collateral to mint JUSD.
// JUSD as the secondary asset of JOJO, can act as margin for positions.
contract JUSD is Context, ERC20, Ownable {
    uint8 _decimals_;

    constructor(uint8 _decimals) ERC20("JUSD Token", "JUSD") {
        _decimals_ = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals_;
    }

    function mint(uint256 amount) external onlyOwner {
        _mint(_msgSender(), amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(_msgSender(), amount);
    }
}
