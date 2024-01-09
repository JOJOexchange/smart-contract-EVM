/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDealer.sol";
import "./DegenSubaccount.sol";

pragma solidity ^0.8.20;

contract DegenSubaccountFactory {
    // ========== storage ==========

    // degenSubaccount template that can be cloned
    address immutable template;

    address immutable dealer;

    address immutable globalOperator;

    // degenSubaccount can only be added.
    mapping(address => address[]) degenSubaccountRegistry;

    // ========== event ==========

    event NewDegenSubaccount(address indexed master, uint256 degenSubaccountIndex, address degenSubaccountAddress);

    constructor(address _dealer, address _operator) {
        template = address(new DegenSubaccount());
        dealer = _dealer;
        globalOperator = _operator;
        DegenSubaccount(template).init(address(this), dealer, globalOperator);
    }

    // ========== functions =======

    /// @notice https://eips.ethereum.org/EIPS/eip-1167[EIP 1167]
    /// is a standard protocol for deploying minimal proxy contracts,
    /// also known as "clones".
    function newSubaccount() external returns (address degenSubaccount) {
        degenSubaccount = Clones.clone(template);
        DegenSubaccount(degenSubaccount).init(msg.sender, dealer, globalOperator);
        degenSubaccountRegistry[msg.sender].push(degenSubaccount);
        emit NewDegenSubaccount(msg.sender, degenSubaccountRegistry[msg.sender].length - 1, degenSubaccount);
    }

    function getDegenSubaccounts(address master) external view returns (address[] memory) {
        return degenSubaccountRegistry[master];
    }

    function getDegenSubaccount(address master, uint256 index) external view returns (address) {
        return degenSubaccountRegistry[master][index];
    }
}
