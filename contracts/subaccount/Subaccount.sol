/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/
import "../intf/IDealer.sol";

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

/// @notice Subaccount can help its owner manage risk and positions.
/// You can achieve isolated positions via Subaccount.
/// You can also let others trade for you by setting them as valid 
/// operators. Operatiors has no access to the fund.
contract Subaccount {
    
    // ========== storage ==========

    /*
       This is not a standard ownable contract because the ownership
       can not be transferred. And the contract is designed to be
       initializable to better support clone, which is a low gas
       deployment solution.
    */
    address public owner;
    bool public initialized;

    // Operator white list. The operator can delegate trading if true.
    mapping(address => bool) validOperator;

    // ========== modifier ==========

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    // ========== functions ==========

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

    /*
        Subaccount can only withdraw asset to its owner.
        No deposit related function because the owner can
        deposit to subaccount directly in Dealer. 
    */

    /// @param dealer As the subaccount can be used with more than one dealer,
    /// you need to pass this address in.
    function withdraw(address dealer, uint256 amount) external onlyOwner {
        IDealer(dealer).withdraw(amount, owner);
    }

    /// @param dealer As the subaccount can be used with more than one dealer,
    /// you need to pass this address in. 
    function withdrawPendingFund(address dealer) external onlyOwner {
        IDealer(dealer).withdrawPendingFund(owner);
    }
}
