/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "./libraries/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DegenDealer is Ownable {
    struct WithdrawInfo {
        address account;
        uint256 amount;
    }

    struct PositionInfo {
        address trader;
        int256 paperAmount;
        int256 creditAmount;
        int256 fee;
        int256 pnl;
        string perp;
    }

    bytes32 public immutable domainSeparator;
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("Withdraw(address account,uint256 amount)");
    address public primaryAsset;
    address public operator;

    using SafeERC20 for IERC20;

    event DegenDeposit(address account, uint256 amount);
    event DegenWithdraw(address account, uint256 amount);
    event PositionFinalizeLog(
        address indexed trader, int256 paperAmount, int256 creditAmount, int256 fee, int256 pnl, string perp
    );

    constructor(address _primaryAsset) {
        primaryAsset = _primaryAsset;
        domainSeparator = EIP712._buildDomainSeparator("JOJODegen", "1", address(this));
    }

    function deposit(address account, uint256 amount) external {
        IERC20(primaryAsset).safeTransferFrom(msg.sender, address(this), amount);
        emit DegenDeposit(account, amount);
    }

    function withdraw(WithdrawInfo memory withdrawInfo, bytes memory signature) external {
        bytes32 hashStruct = keccak256(abi.encode(WITHDRAW_TYPEHASH, withdrawInfo.account, withdrawInfo.amount));
        bytes32 withdrawHash = EIP712._hashTypedDataV4(domainSeparator, hashStruct);
        (address recoverSigner,) = ECDSA.tryRecover(withdrawHash, signature);
        require(recoverSigner == operator, "INVALID_ORDER_SIGNATURE");
        require(withdrawInfo.account == msg.sender);
        IERC20(primaryAsset).safeTransfer(msg.sender, withdrawInfo.amount);
        emit DegenWithdraw(msg.sender, withdrawInfo.amount);
    }

    function updateGlobalOperator(address newOperator) public onlyOwner {
        operator = newOperator;
    }

    function batchUpdatePosition(PositionInfo[] memory positionDatas) public onlyOwner {
        for (uint256 i; i < positionDatas.length; i++) {
            PositionInfo memory position = positionDatas[i];
            emit PositionFinalizeLog(
                position.trader, position.paperAmount, position.creditAmount, position.fee, position.pnl, position.perp
            );
        }
    }
}
