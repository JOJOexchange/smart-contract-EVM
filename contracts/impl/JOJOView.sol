/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JOJOStorage.sol";
import "../lib/Liquidation.sol";
import "../utils/Errors.sol";

contract JOJOView is JOJOStorage {
    function getFundingRatio(address perpetualAddress)
        external
        view
        returns (int256)
    {
        return state.perpRiskParams[perpetualAddress].fundingRatio;
    }

    function getRegisteredPerp() external view returns (address[] memory) {
        return state.registeredPerp;
    }

    function getCreditOf(address trader)
        external
        view
        returns (int256 trueCredit, uint256 virtualCredit)
    {
        trueCredit = state.trueCredit[trader];
        virtualCredit = state.virtualCredit[trader];
    }

    function getOrderHash(Types.Order memory order)
        external
        view
        returns (bytes32 orderHash)
    {
        orderHash = EIP712._hashTypedDataV4(
            state.domainSeparator,
            keccak256(
                abi.encode(
                    Types.ORDER_TYPEHASH,
                    order.perp,
                    order.paperAmount,
                    order.creditAmount,
                    order.makerFeeRate,
                    order.takerFeeRate,
                    order.signer,
                    order.orderSender,
                    order.expiration,
                    order.nounce
                )
            )
        );
        return orderHash;
    }

    function getTraderRisk(address trader)
        external
        view
        returns (
            int256 positionNetValue,
            uint256 exposure,
            int256 trueCredit,
            uint256 virtualCredit
        )
    {
        (positionNetValue, exposure, ) = Liquidation._getTotalExposure(
            state,
            trader
        );
        trueCredit = state.trueCredit[trader];
        virtualCredit = state.virtualCredit[trader];
    }

    // return 0 if the trader can not be liquidated
    function getLiquidationPrice(address trader, address perp)
        external
        view
        returns (uint256 liquidationPrice)
    {
        return Liquidation._getLiquidationPrice(state, trader, perp);
    }
}
