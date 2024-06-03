/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockMUSDC is ERC20 {
    // add this to be excluded from coverage report
    function test() public { }

    uint8 _decimals_;
    address public usdc;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address _usdc) ERC20(name_, symbol_) {
        _decimals_ = decimals_;
        usdc = _usdc;
    }

    function decimals() public view override returns (uint8) {
        return _decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function mint(uint256 amount) external{
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 50 * 1e2);
    }

    function mintBatch(address[] calldata to, uint256[] calldata amount) external {
        for (uint256 i = 0; i < to.length; i++) {
            _mint(to[i], amount[i]);
        }
    }

    function deposit() public payable { }

    function redeem(uint256 redeemTokens) external returns (uint256) {
        uint256 amount = redeemTokens * 2 / 1e4;
        IERC20(usdc).transfer(msg.sender, amount);
        return amount;
    }
}
