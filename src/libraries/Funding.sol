/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/internal/IPriceSource.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/Errors.sol";
import "../libraries/SignedDecimalMath.sol";
import "./Liquidation.sol";
import "./Operation.sol";
import "./Types.sol";

library Funding {
    using SafeERC20 for IERC20;

    // ========== events ==========

    event Deposit(address indexed to, address indexed payer, uint256 primaryAmount, uint256 secondaryAmount);

    event Withdraw(address indexed to, address indexed payer, uint256 primaryAmount, uint256 secondaryAmount);

    event RequestWithdraw(
        address indexed payer, uint256 primaryAmount, uint256 secondaryAmount, uint256 executionTimestamp
    );

    event TransferIn(address trader, uint256 primaryAmount, uint256 secondaryAmount);

    event TransferOut(address trader, uint256 primaryAmount, uint256 secondaryAmount);

    // ========== deposit ==========

    function deposit(Types.State storage state, uint256 primaryAmount, uint256 secondaryAmount, address to) external {
        if (primaryAmount > 0) {
            IERC20(state.primaryAsset).safeTransferFrom(msg.sender, address(this), primaryAmount);
            state.primaryCredit[to] += SafeCast.toInt256(primaryAmount);
        }
        if (secondaryAmount > 0) {
            IERC20(state.secondaryAsset).safeTransferFrom(msg.sender, address(this), secondaryAmount);
            state.secondaryCredit[to] += secondaryAmount;
        }
        emit Deposit(to, msg.sender, primaryAmount, secondaryAmount);
    }

    // ========== withdraw ==========

    function isWithdrawValid(
        Types.State storage state,
        address spender,
        address from,
        uint256 primaryAmount,
        uint256 secondaryAmount
    )
        internal
        view
        returns (bool)
    {
        return spender == from
            || (
                state.primaryCreditAllowed[from][spender] >= primaryAmount
                    && state.secondaryCreditAllowed[from][spender] >= secondaryAmount
            );
    }

    function requestWithdraw(
        Types.State storage state,
        address from,
        uint256 primaryAmount,
        uint256 secondaryAmount
    )
        external
    {
        require(isWithdrawValid(state, msg.sender, from, primaryAmount, secondaryAmount), Errors.WITHDRAW_INVALID);
        state.pendingPrimaryWithdraw[msg.sender] = primaryAmount;
        state.pendingSecondaryWithdraw[msg.sender] = secondaryAmount;
        state.withdrawExecutionTimestamp[msg.sender] = block.timestamp + state.withdrawTimeLock;
        emit RequestWithdraw(msg.sender, primaryAmount, secondaryAmount, state.withdrawExecutionTimestamp[msg.sender]);
    }

    function executeWithdraw(
        Types.State storage state,
        address from,
        address to,
        bool isInternal,
        bytes memory param
    )
        external
    {
        require(state.withdrawExecutionTimestamp[from] <= block.timestamp, Errors.WITHDRAW_PENDING);
        uint256 primaryAmount = state.pendingPrimaryWithdraw[from];
        uint256 secondaryAmount = state.pendingSecondaryWithdraw[from];
        require(isWithdrawValid(state, msg.sender, from, primaryAmount, secondaryAmount), Errors.WITHDRAW_INVALID);
        state.pendingPrimaryWithdraw[from] = 0;
        state.pendingSecondaryWithdraw[from] = 0;
        // No need to change withdrawExecutionTimestamp, because we set pending
        // withdraw amount to 0.
        _withdraw(state, msg.sender, from, to, primaryAmount, secondaryAmount, isInternal, param);
    }

    function fastWithdraw(
        Types.State storage state,
        address from,
        address to,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isInternal,
        bytes memory param
    )
        external
    {
        require(
            !state.fastWithdrawDisabled || state.fastWithdrawalWhitelist[msg.sender], Errors.FAST_WITHDRAW_NOT_ALLOWED
        );
        require(isWithdrawValid(state, msg.sender, from, primaryAmount, secondaryAmount), Errors.WITHDRAW_INVALID);
        _withdraw(state, msg.sender, from, to, primaryAmount, secondaryAmount, isInternal, param);
    }

    function _withdraw(
        Types.State storage state,
        address spender,
        address from,
        address to,
        uint256 primaryAmount,
        uint256 secondaryAmount,
        bool isInternal,
        bytes memory param
    )
        private
    {
        if (spender != from) {
            state.primaryCreditAllowed[from][spender] -= primaryAmount;
            state.secondaryCreditAllowed[from][spender] -= secondaryAmount;
            emit Operation.FundOperatorAllowedChange(
                from, spender, state.primaryCreditAllowed[from][spender], state.secondaryCreditAllowed[from][spender]
            );
        }
        if (primaryAmount > 0) {
            state.primaryCredit[from] -= SafeCast.toInt256(primaryAmount);
            if (isInternal) {
                state.primaryCredit[to] += SafeCast.toInt256(primaryAmount);
            } else {
                IERC20(state.primaryAsset).safeTransfer(to, primaryAmount);
            }
        }
        if (secondaryAmount > 0) {
            state.secondaryCredit[from] -= secondaryAmount;
            if (isInternal) {
                state.secondaryCredit[to] += secondaryAmount;
            } else {
                IERC20(state.secondaryAsset).safeTransfer(to, secondaryAmount);
            }
        }

        if (primaryAmount > 0) {
            // if trader withdraw primary asset, we should check if solid safe
            require(Liquidation._isSolidIMSafe(state, from), Errors.ACCOUNT_NOT_SAFE);
        } else {
            // if trader didn't withdraw primary asset, normal safe check is enough
            require(Liquidation._isIMSafe(state, from), Errors.ACCOUNT_NOT_SAFE);
        }

        if (isInternal) {
            emit TransferIn(to, primaryAmount, secondaryAmount);
            emit TransferOut(from, primaryAmount, secondaryAmount);
        } else {
            emit Withdraw(to, from, primaryAmount, secondaryAmount);
        }

        if (param.length != 0) {
            require(Address.isContract(to), "target is not a contract");
            (bool success,) = to.call(param);
            if (success == false) {
                assembly {
                    let ptr := mload(0x40)
                    let size := returndatasize()
                    returndatacopy(ptr, 0, size)
                    revert(ptr, size)
                }
            }
        }
    }
}
