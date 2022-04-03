/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/
import "../intf/IDealer.sol";

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

contract Subaccount {
    address public owner;
    bool public initialized;
    mapping(address => bool) validOperator;

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function init(address _owner) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
    }

    function isValidPerpetualOperator(address o) external view returns (bool) {
        return o == owner || validOperator[o];
    }

    function setOperator(address o, bool isValid) external onlyOwner {
        validOperator[o] = isValid;
    }

    function withdraw(address dealer, uint256 amount) external onlyOwner {
        IDealer(dealer).withdraw(amount, owner);
    }

    function withdrawPendingFund(address dealer) external onlyOwner {
        IDealer(dealer).withdrawPendingFund(owner);
    }
}
