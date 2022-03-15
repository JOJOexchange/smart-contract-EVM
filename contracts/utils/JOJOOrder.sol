pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../intf/ITradingProxy.sol";
import "./Errors.sol";

contract JOJOOrder is EIP712("JOJO Order", "1") {
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(address perp, int256 paperAmount, int256 creditAmount, int128 makerFeeRate, int128 takerFeeRate, address signer, address sender, uint256 expiration, uint256 salt)"
        );

    // if you want to open long positon, set paperAmount > 0 and creditAmount < 0
    // if the sender want to charge fee, set feeRate < 0; if the sender want to rebate, set feeRate > 0;
    struct Order {
        address perp;
        int256 paperAmount;
        int256 creditAmount;
        int128 makerFeeRate;
        int128 takerFeeRate;
        address signer;
        address orderSender;
        uint256 expiration;
        uint256 salt;
    }

    function validateOrder(
        Order memory order,
        bytes memory signature
    ) external returns (bytes32 orderHash) {
        orderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.perp,
                    order.paperAmount,
                    order.creditAmount,
                    order.signer,
                    order.orderSender,
                    order.expiration,
                    order.salt
                )
            )
        );
        if (Address.isContract(order.signer)) {
            require(
                ITradingProxy(order.signer).isValidPerpetualOperator(
                    ECDSA.recover(orderHash, signature)
                ),
                Errors.INVALID_ORDER_SIGNATURE
            );
        } else {
            require(
                ECDSA.recover(orderHash, signature) == order.signer,
                Errors.INVALID_ORDER_SIGNATURE
            );
        }
        require(
            (order.paperAmount < 0 && order.creditAmount > 0) ||
                (order.paperAmount > 0 && order.creditAmount < 0),
            "ORDER PRICE NEGATIVE"
        );
    }
}
