pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

import "./JOJOTrading.sol";

contract JOJODealer is JOJOTrading {

    // Construct
    constructor(address _underlyingAsset, address _insurance) JOJOTrading() {
        underlyingAsset = _underlyingAsset;
        insurance = _insurance;
    }

}