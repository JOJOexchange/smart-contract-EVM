/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/brevis/IBrevisProof.sol";
import "./libraries/brevis/BrevisApp.sol";
import "./interfaces/internal/IPriceSource.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/IPerpetual.sol";
import "./libraries/Types.sol";
import "./libraries/SignedDecimalMath.sol";

/// @notice Limiting funding rate change speed
/// Mainly for preventing JOJO's backend errors
/// and to prevent mischief
contract FundingRateUpdateZk is Ownable, BrevisApp {
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

    int248 public btcRateLimit;

    bytes32 public vkHash;

    constructor(address _dealer, uint8 _speedMultiplier, address brevisProof) BrevisApp(IBrevisProof(brevisProof)) {
        dealer = _dealer;
        speedMultiplier = _speedMultiplier;
    }

    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }

    // BrevisQuery contract will call our callback once Brevis backend submits the proof.
    function handleProofResult(bytes32, bytes32 _vkHash, bytes calldata _circuitOutput) internal override {
        require(vkHash == _vkHash, "invalid vk");
        (uint64 symbol, uint248 limitRate) = decodeOutput(_circuitOutput);
        if(symbol == 0){
            btcRateLimit = int248(limitRate);
        } else {
            btcRateLimit = -int248(limitRate);
        }
    }

    function decodeOutput(bytes calldata output) internal pure returns (uint64, uint248) {
        uint64 symbol = uint64(bytes8(output[0:8]));
        uint248 limitRate = uint248(bytes31(output[8:8 + 31]));
        return (symbol, limitRate);
    }

    function updateFundingRate(address perp, int256 rate) external onlyOwner {
        int256 oldRate = IPerpetual(perp).getFundingRate();
        uint256 maxChange = getMaxChange(perp);
        require((rate - oldRate).abs() <= maxChange, "FUNDING_RATE_CHANGE_TOO_MUCH");
        fundingRateUpdateTimestamp[perp] = block.timestamp;
        address[] memory perpList = new address[](1);
        perpList[0] = perp;
        int256[] memory rateList = new int256[](1);
        rateList[0] = rate;

        IDealer(dealer).updateFundingRate(perpList, rateList);
    }

    // limit funding rate change speed
    // can not exceed speedMultiplier*liquidationThreshold
    function getMaxChange(address perp) public view returns (uint256) {
        Types.RiskParams memory params = IDealer(dealer).getRiskParams(perp);
        uint256 markPrice = IPriceSource(params.markPriceSource).getMarkPrice();
        uint256 timeInterval = block.timestamp - fundingRateUpdateTimestamp[perp];
        uint256 maxChangeRate = (speedMultiplier * timeInterval * params.liquidationThreshold) / (1 days);
        uint256 maxChange = (maxChangeRate * markPrice) / Types.ONE;
        return maxChange;
    }
}
