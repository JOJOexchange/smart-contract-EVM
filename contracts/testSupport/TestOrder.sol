/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/

pragma solidity 0.8.9;

import "../lib/EIP712.sol";
import "../lib/Types.sol";

contract TestOrder {
    function getOrderHash(bytes32 domainSeparator, Types.Order memory order)
        external
        pure
        returns (bytes32 orderHash)
    {
        orderHash = EIP712._hashTypedDataV4(
            domainSeparator,
            _structHash(order)
        );
    }

    function _structHash(Types.Order memory order)
        private
        pure
        returns (bytes32 structHash)
    {
        /*
            To save gas, we use assembly to implement the function:

            keccak256(
                abi.encode(
                    Types.ORDER_TYPEHASH,
                    order.perp,
                    order.signer,
                    order.orderSender,
                    order.paperAmount,
                    order.creditAmount,
                    order.info
                )
            )

            Method:
            Insert ORDER_TYPEHASH before order's memory head to construct the
            required memory structure. Get the hash of this structure and then
            restore it as is.
        */

        bytes32 orderTypeHash = Types.ORDER_TYPEHASH;
        assembly {
            let start := sub(order, 32)
            let tmp := mload(start)
            // 224 = (1 + 6) * 32
            // [0...32)   bytes: EIP712_ORDER_TYPE
            // [32...224) bytes: order
            mstore(start, orderTypeHash)
            structHash := keccak256(start, 224)
            mstore(start, tmp)
        }
    }
}
