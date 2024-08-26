/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DegenDealer.sol";

pragma solidity ^0.8.19;

contract DegenDepositHelper is Ownable {
    using SafeERC20 for IERC20;

    address public immutable usdc;
    address public immutable degenDealer;

    mapping(address => bool) public adminWhiteList;

    event UpdateAdmin(address admin, bool isValid);
    event PerpDepositToDegen(address from, address to, uint256 amount);

    constructor(address _usdc, address _degenDealer) Ownable() {
        usdc = _usdc;
        degenDealer = _degenDealer;
    }

    modifier onlyAdminWhiteList() {
        require(adminWhiteList[msg.sender], "caller is not in the admin white list");
        _;
    }

    function setWhiteList(address admin, bool isValid) external onlyOwner {
        adminWhiteList[admin] = isValid;
        emit UpdateAdmin(admin, isValid);
    }

    function depositToDegenDealer(address to) external onlyAdminWhiteList {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        require(usdcBalance > 0, "need to transfer usdc first");
        IERC20(usdc).approve(degenDealer, usdcBalance);
        DegenDealer(degenDealer).deposit(msg.sender, to, usdcBalance);
    }
}
