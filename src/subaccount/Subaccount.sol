/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Subaccount can help its owner manage risk and positions.
/// You can open orders with isolated positions via Subaccount.
/// You can also let others trade for you by setting them as authorized
/// operators. Operators have no access to fund transfer.
contract Subaccount {
    // ========== storage ==========

    /*
       This is not a standard ownable contract because the ownership
       can not be transferred. This contract is designed to be
       initializable to better support clone, which is a low gas
       deployment solution.
    */
    address public owner;
    bool public initialized;

    // ========== modifier ==========

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    // ========== event ==========
    event ExecuteTransaction(address indexed owner, address subaccount, address to, bytes data, uint256 value);

    // ========== functions ==========

    function init(address _owner) external {
        require(!initialized, "ALREADY INITIALIZED");
        initialized = true;
        owner = _owner;
    }

    function execute(
        address to,
        bytes calldata data,
        uint256 value
    )
        external
        payable
        onlyOwner
        returns (bytes memory)
    {
        require(to != address(0), "execute address is empty");
        require(msg.value == value, "TRANSFER_PAYMENT_NOT_MATCH");
        (bool success, bytes memory returnData) = to.call{ value: value }(data);
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        emit ExecuteTransaction(owner, address(this), to, data, value);
        return returnData;
    }
}
