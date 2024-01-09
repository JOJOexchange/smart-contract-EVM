/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDealer.sol";
import "./BotSubaccount.sol";

pragma solidity ^0.8.20;

contract BotSubaccountFactory {
    // ========== storage ==========

    // botSubaccount template that can be cloned
    address immutable template;

    address immutable dealer;

    address immutable globalOperator;

    mapping(address => address[]) botSubaccountRegistry;

    // ========== event ==========

    event NewBotSubaccount(
        address indexed master, address indexed operator, uint256 botSubaccountIndex, address botSubaccountAddress
    );

    // ========== constructor ==========

    constructor(address _dealer, address _operator) {
        template = address(new BotSubaccount());
        dealer = _dealer;
        globalOperator = _operator;
        BotSubaccount(template).init(address(this), address(this), dealer, globalOperator);
    }

    // ========== functions ==========

    /// @notice https://eips.ethereum.org/EIPS/eip-1167[EIP 1167]
    /// is a standard protocol for deploying minimal proxy contracts,
    /// also known as "clones".
    // owner should be the EOA
    function newSubaccount(address owner, address operator) external returns (address botSubaccount) {
        botSubaccount = Clones.clone(template);
        BotSubaccount(botSubaccount).init(owner, operator, dealer, globalOperator);
        botSubaccountRegistry[owner].push(botSubaccount);
        emit NewBotSubaccount(owner, operator, botSubaccountRegistry[owner].length - 1, botSubaccount);
    }

    function getBotSubaccounts(address master) external view returns (address[] memory) {
        return botSubaccountRegistry[master];
    }

    function getBotSubaccount(address master, uint256 index) external view returns (address) {
        return botSubaccountRegistry[master][index];
    }
}
