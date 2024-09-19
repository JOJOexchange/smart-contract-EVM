/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../libraries/brevis/IBrevisProof.sol";
import "../libraries/brevis/BrevisApp.sol";
import "../interfaces/internal/IPriceSource.sol";
import "../interfaces/IDealer.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/Types.sol";
import "../libraries/SignedDecimalMath.sol";

/// @notice Limiting funding rate change speed
/// Mainly for preventing JOJO's backend errors
/// and to prevent mischief
contract FundingRateUpdateLimiterZK is Ownable, BrevisApp {
    using SignedDecimalMath for int256;
    using SafeCast for uint248;
    using SafeCast for uint256;
    using SafeCast for int256;

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
    // funding rate by zk proof, aligned with frontend
    mapping(address => int256) public fundingRateByZK;
    // for zk proof
    bytes32 public vkHash;

    constructor(
        address _dealer,
        uint8 _speedMultiplier,
        address brevisProof
    ) BrevisApp(IBrevisProof(brevisProof)) {
        dealer = _dealer;
        speedMultiplier = _speedMultiplier;
    }

    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }

    // BrevisQuery contract will call our callback once Brevis backend submits the proof.
    function handleProofResult(
        bytes32,
        bytes32 _vkHash,
        bytes calldata _circuitOutput
    ) internal override {
        require(vkHash == _vkHash, "invalid vk");
        (address perp, bool isPositve, uint248 limitRate) = decodeOutput(
            _circuitOutput
        );
        fundingRateByZK[perp] = isPositve
            ? limitRate.toInt256()
            : -limitRate.toInt256();
    }

    function decodeOutput(
        bytes calldata output
    ) internal pure returns (address perp, bool isPositve, uint248 limitRate) {
        require(output.length == 20 + 1 + 31, "INVALID_OUTPUT_LENGTH");
        perp = address(bytes20(output[0:20]));
        isPositve = uint8(output[20]) == 1;
        limitRate = uint248(bytes31(output[21:21 + 31]));
    }

    function resetFundRateByZK(address perp) external onlyOwner {
        fundingRateByZK[perp] = 0;
    }

    function updateFundingRate(
        address[] calldata perpList,
        int256[] calldata rateList
    ) external onlyOwner {
        require(perpList.length == rateList.length, "Array lengths mismatch");

        for (uint256 i = 0; i < perpList.length; ) {
            address perp = perpList[i];
            int256 newRate = rateList[i];

            require(
                isNewRateValid(perp, newRate),
                "FUNDING_RATE_CHANGE_TOO_MUCH"
            );

            fundingRateUpdateTimestamp[perp] = block.timestamp;

            unchecked {
                ++i;
            }
        }

        IDealer(dealer).updateFundingRate(perpList, rateList);
    }

    // limit funding rate change speed
    // can not exceed speedMultiplier*liquidationThreshold
    function rateBoundry(
        address perp
    ) public view returns (int256 lowerBoundary, int256 upperBoundary) {
        int256 oldRate = IPerpetual(perp).getFundingRate();
        Types.RiskParams memory params = IDealer(dealer).getRiskParams(perp);
        uint256 markPrice = IPriceSource(params.markPriceSource).getMarkPrice();
        uint256 timeInterval = block.timestamp -
            fundingRateUpdateTimestamp[perp];
        int256 maxChange = ((((speedMultiplier *
            timeInterval *
            params.liquidationThreshold) / (1 days)) * markPrice) / Types.ONE)
            .toInt256();
        int256 fundingRateCahngeByZK = (fundingRateByZK[perp] *
            markPrice.toInt256()) / 1e18;
        lowerBoundary = oldRate + fundingRateCahngeByZK - maxChange;
        upperBoundary = oldRate + fundingRateCahngeByZK + maxChange;
    }

    function isNewRateValid(
        address perp,
        int256 newRate
    ) public view returns (bool) {
        (int256 lowerBoundary, int256 upperBoundary) = rateBoundry(perp);
        return newRate >= lowerBoundary && newRate <= upperBoundary;
    }
}
