/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Subaccount.sol";

pragma solidity 0.8.9;

contract SubaccountFactory {
    // ========== storage ==========

    // Subaccount can only be added.
    mapping(address => address[]) subaccountRegistry;

    // ========== event ==========

    event NewSubaccount(
        address indexed master,
        uint256 subaccountIndex,
        address subaccountAddress
    );

    // ========== functions ==========

    function newSubaccount() external returns(address) {
        Subaccount subaccount = new Subaccount();
        subaccount.init(msg.sender);
        subaccountRegistry[msg.sender].push(address(subaccount));
        emit NewSubaccount(
            msg.sender,
            subaccountRegistry[msg.sender].length - 1,
            address(subaccount)
        );
        return address(subaccount);
    }

    function getSubaccounts(address master)
        external
        view
        returns (address[] memory)
    {
        return subaccountRegistry[master];
    }

    function getSubaccount(address master, uint256 index)
        external
        view
        returns (address)
    {
        return subaccountRegistry[master][index];
    }
}
