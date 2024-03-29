/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/internal/IPyth.sol";

contract PythOracleAdaptor is Ownable {
    IPyth public pyth;

    constructor(address _pythContract) {
        pyth = IPyth(_pythContract);
    }

    function setMarkPrice(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    )
        external
        payable
        onlyOwner
    {
        // Update the on-chain Pyth price(s)
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeedsIfNecessary{ value: fee }(updateData, priceIds, publishTimes);
    }
}
