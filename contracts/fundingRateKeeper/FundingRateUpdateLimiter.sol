/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../intf/IDealer.sol";
import "../intf/IPerpetual.sol";
import "../intf/IMarkPriceSource.sol";
import "../utils/SignedDecimalMath.sol";
import "../lib/Types.sol";

/// @notice Limiting funding rate change speed
/// Mainly for preventing JOJO's backend errors
/// and to prevent mischief
contract FundingRateUpdateLimiter is Ownable {
    using SignedDecimalMath for int256;

    // dealer
    address immutable dealer;
    // max speed multiplier, should be 1/2/3/4/5..., no decimal
    // funding rate max daily change will be limited to 
    // speedMultiplier*liquidationThreshold
    // e.d 3 * 3% = 9%
    uint8 immutable speedMultiplier;
    // The timestamp of the last funding rate update
    // used to limit the change rate of fundingRate
    mapping(address => uint256) public fundingRateUpdateTimestamp;

    constructor(address _dealer, uint8 _speedMultiplier) {
        dealer = _dealer;
        speedMultiplier = _speedMultiplier;
    }

    function updateFundingRate(
        address[] calldata perpList,
        int256[] calldata rateList
    ) external onlyOwner {
        for (uint256 i = 0; i < perpList.length;) {
            address perp = perpList[i];
            require(
                (rateList[i]).abs() <= 1e16,
                "FUNDING_RATE_CHANGE_TOO_MUCH"
            );
            fundingRateUpdateTimestamp[perp] = block.timestamp;
            unchecked {
                ++i;
            }
        }

        IDealer(dealer).updateFundingRate(perpList, rateList);
    }
}
