pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "./JOJOTrading.sol";

contract JOJODealer is JOJOTrading {
    // Construct
    constructor(
        address _underlyingAsset,
        address _insurance,
        address _orderValidator
    ) JOJOTrading() {
        underlyingAsset = _underlyingAsset;
        insurance = _insurance;
        orderValidator = _orderValidator;
    }
}
