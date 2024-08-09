/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/llo-feeds/v0.3.0/interfaces/IVerifierProxy.sol";
import "../interfaces/internal/IChainlink.sol";

// 1. verify report
// 2. cache recent report
// 3. getPrice 如果 start timestamp 比 Chainlink 数据靠后，就用 ds 的，否则用 Chainlink 的
// https://docs.chain.link/data-streams/tutorials/streams-direct/streams-direct-onchain-verification

struct Report {
    bytes32 feedId; // The feed ID the report has data for
    uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
    uint32 observationsTimestamp; // Latest timestamp for which price is applicable
    uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
    uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
    uint32 expiresAt; // Latest timestamp where the report can be verified onchain
    int192 price; // DON consensus median price (8 or 18 decimals)
    int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation (8 or 18 decimals)
    int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation (8 or 18 decimals)
}

struct PriceSources {
    IChainlink chainlinkFeed;
    uint256 feedDecimalsCorrection;
    Report lastDSReport;
    uint256 DSDecimalCorrection;
    uint256 heartBeat;
    string name;
}

contract ChainlinkDSPortal is Ownable {
    // get variable price
    address public immutable dsVerifyProxy;
    mapping(bytes32 => PriceSources) public priceSourcesMap;

    // correct it to usdc price in right decimal
    uint256 public immutable usdcHeartbeat;
    address public immutable usdcSource;

    event VerifyReport(bytes32 key);

    constructor(
        address _dsVerifyProxy,
        uint256 _usdcHeartbeat,
        address _usdcSource
    ) {
        dsVerifyProxy = _dsVerifyProxy;
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
    }

    function _stringToBytes32(
        string memory source
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(source));
    }

    function _verifyReport(
        bytes memory unverifiedReport
    ) private returns (Report memory) {
        // Verify the report
        bytes memory verifiedReportData = IVerifierProxy(dsVerifyProxy).verify(
            unverifiedReport,
            abi.encode(address(this)) // todo need a token address here
        );

        // Decode verified report data into a Report struct
        // If your report is a PremiumReport, you should decode it as a PremiumReport
        Report memory verifiedReport = abi.decode(verifiedReportData, (Report));
        return verifiedReport;
    }

    function newPriceSource(
        string memory name,
        address _chainlinkFeed,
        uint256 feedDecimalCorrection,
        uint256 _DSDecimalCorrection,
        uint256 _heartBeat
    ) public onlyOwner {
        Report memory emptyReport = Report({
            feedId: bytes32(0),
            validFromTimestamp: 0,
            observationsTimestamp: 0,
            nativeFee: 0,
            linkFee: 0,
            expiresAt: 0,
            price: 0,
            bid: 0,
            ask: 0
        });
        bytes32 key = _stringToBytes32(name);
        priceSourcesMap[key] = PriceSources({
            chainlinkFeed: IChainlink(_chainlinkFeed),
            feedDecimalsCorrection: 10 ** feedDecimalCorrection,
            lastDSReport: emptyReport,
            DSDecimalCorrection: 10 ** _DSDecimalCorrection,
            heartBeat: _heartBeat,
            name: name
        });
    }

    function resetPriceSource(
        string memory name,
        address _chainlinkFeed,
        uint256 feedDecimalCorrection,
        uint256 _DSDecimalCorrection,
        uint256 _heartBeat
    ) public onlyOwner {
        bytes32 key = _stringToBytes32(name);
        PriceSources storage priceSources = priceSourcesMap[key];
        priceSources.chainlinkFeed = IChainlink(_chainlinkFeed);
        priceSources.feedDecimalsCorrection = 10 ** feedDecimalCorrection;
        priceSources.DSDecimalCorrection = 10 ** _DSDecimalCorrection;
        priceSources.heartBeat = _heartBeat;
    }

    function verifyReports(
        string[] memory names,
        bytes[] memory unverifiedReports
    ) public onlyOwner {
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = _stringToBytes32(names[i]);
            PriceSources storage priceSources = priceSourcesMap[key];
            priceSources.lastDSReport = _verifyReport(unverifiedReports[i]);
            emit VerifyReport(key);
        }
    }

    function getUSDCPrice() public view returns (uint256) {
        (, int256 usdcPrice, , uint256 usdcUpdatedAt, ) = IChainlink(usdcSource)
            .latestRoundData();

        require(
            block.timestamp - usdcUpdatedAt <= usdcHeartbeat,
            "USDC_ORACLE_HEARTBEAT_FAILED"
        );

        return SafeCast.toUint256(usdcPrice);
    }

    function getPriceByName(
        string memory name
    ) public view returns (uint256 price) {
        bytes32 key = _stringToBytes32(name);
        return getPriceByKey(key);
    }

    function getPriceByKey(bytes32 key) public view returns (uint256 price) {
        PriceSources memory priceSources = priceSourcesMap[key];
        Report memory DSReport = priceSources.lastDSReport;

        // Get original chainlink feed price
        int256 feedPrice;
        uint256 feedUpdatedAt;
        if (address(priceSources.chainlinkFeed) != address(0)) {
            (, feedPrice, , feedUpdatedAt, ) = priceSources
                .chainlinkFeed
                .latestRoundData();
        }
        // Get DS report price
        uint256 latestTimestamp;
        require(DSReport.validFromTimestamp > 0 || feedUpdatedAt > 0);
        if (DSReport.validFromTimestamp > feedUpdatedAt) {
            latestTimestamp = DSReport.validFromTimestamp;
            price =
                (SafeCast.toUint256(DSReport.price) * 1e18) /
                priceSources.DSDecimalCorrection;
        } else {
            latestTimestamp = feedUpdatedAt;
            price =
                (SafeCast.toUint256(feedPrice) * 1e18) /
                priceSources.feedDecimalsCorrection;
        }
        // check heartbeat
        require(
            block.timestamp - latestTimestamp <= priceSources.heartBeat,
            "ORACLE_HEARTBEAT_FAILED"
        );

        return (price * 1e8) / getUSDCPrice();
    }
}

contract ChainlinkDSAdaptor {
    address portal;
    bytes32 key;

    constructor(string memory tradingPairName) {
        key = keccak256(abi.encodePacked(tradingPairName));
    }

    function getMarkPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }

    function getAssetPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }
}
