/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Subaccount.sol";

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

contract SubaccountFactory {
    address immutable template;
    mapping(address => address[]) subaccountRegistry;

    event NewSubaccount(address indexed master, uint256 index);

    constructor() {
        template = address(new Subaccount());
        Subaccount(template).init(address(this));
    }

    function newSubaccount() external returns (address subaccount) {
        require(!Address.isContract(msg.sender), "ONLY EOA CAN CREATE SUBACCOUNT");
        subaccount = Clones.clone(template);
        Subaccount(subaccount).init(msg.sender);
        subaccountRegistry[msg.sender].push(subaccount);
        emit NewSubaccount(
            msg.sender,
            subaccountRegistry[msg.sender].length - 1
        );
    }

    function getSubaccounts(address master)
        external
        view
        returns (address[] memory)
    {
        return subaccountRegistry[master];
    }
}
