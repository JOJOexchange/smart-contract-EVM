/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IRewardManager.sol";
import "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import "../interfaces/internal/IChainlink.sol";

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

// Custom interfaces for IVerifierProxy and IFeeManager
interface IVerifierProxy {
    /**
     * @notice Verifies that the data encoded has been signed.
     * correctly by routing to the correct verifier, and bills the user if applicable.
     * @param payload The encoded data to be verified, including the signed
     * report.
     * @param parameterPayload Fee metadata for billing. In the current implementation,
     * this consists of the abi-encoded address of the ERC-20 token used for fees.
     * @return verifierResponse The encoded report from the verifier.
     */
    function verify(
        bytes calldata payload,
        bytes calldata parameterPayload
    ) external payable returns (bytes memory verifierResponse);

    /**
     * @notice Verifies multiple reports in bulk, ensuring that each is signed correctly,
     * routes them to the appropriate verifier, and handles billing for the verification process.
     * @param payloads An array of encoded data to be verified, where each entry includes
     * the signed report.
     * @param parameterPayload Fee metadata for billing. In the current implementation,
     * this consists of the abi-encoded address of the ERC-20 token used for fees.
     * @return verifiedReports An array of encoded reports returned from the verifier.
     */
    function verifyBulk(
        bytes[] calldata payloads,
        bytes calldata parameterPayload
    ) external payable returns (bytes[] memory verifiedReports);

    function s_feeManager() external view returns (IVerifierFeeManager);
}

interface IFeeManager {
    /**
     * @notice Calculates the fee and reward associated with verifying a report, including discounts for subscribers.
     * This function assesses the fee and reward for report verification, applying a discount for recognized subscriber addresses.
     * @param subscriber The address attempting to verify the report. A discount is applied if this address
     * is recognized as a subscriber.
     * @param unverifiedReport The report data awaiting verification. The content of this report is used to
     * determine the base fee and reward, before considering subscriber discounts.
     * @param quoteAddress The payment token address used for quoting fees and rewards.
     * @return fee The fee assessed for verifying the report, with subscriber discounts applied where applicable.
     * @return reward The reward allocated to the caller for successfully verifying the report.
     * @return totalDiscount The total discount amount deducted from the fee for subscribers.
     */
    function getFeeAndReward(
        address subscriber,
        bytes memory unverifiedReport,
        address quoteAddress
    ) external returns (Common.Asset memory, Common.Asset memory, uint256);

    function i_linkAddress() external view returns (address);

    function i_nativeAddress() external view returns (address);

    function i_rewardManager() external view returns (address);
}

// correction decimal
struct PriceSources {
    IChainlink chainlinkFeed;
    uint256 feedDecimalsCorrection;
    Report lastDSReport;
    bytes32 DSFeedId;
    uint256 DSRoundId;
    uint256 DSDecimalCorrection;
    uint256 heartBeat;
    string name;
}

contract ChainlinkDSPortal is Ownable {
    // chainlink datastream proxy
    IVerifierProxy public immutable dsVerifyProxy;

    // registered sources
    string[] public registeredNames;
    mapping(bytes32 => PriceSources) public priceSourcesMap;

    // correct it to usdc price in right decimal
    uint256 public immutable usdcHeartbeat;
    address public immutable usdcSource;

    event AnswerUpdated(
        int256 indexed current,
        bytes32 indexed feedID,
        uint256 indexed roundId,
        uint256 updatedAt,
        string name
    );

    constructor(
        address _dsVerifyProxy,
        uint256 _usdcHeartbeat,
        address _usdcSource
    ) {
        dsVerifyProxy = IVerifierProxy(_dsVerifyProxy);
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
    }

    function nameToKey(string memory name) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function _verifyReport(
        bytes memory unverifiedReport
    ) private returns (Report memory) {
        // Report verification fees
        IFeeManager feeManager = IFeeManager(
            address(dsVerifyProxy.s_feeManager())
        );

        IRewardManager rewardManager = IRewardManager(
            address(feeManager.i_rewardManager())
        );

        (, /* bytes32[3] reportContextData */ bytes memory reportData) = abi
            .decode(unverifiedReport, (bytes32[3], bytes));

        address feeTokenAddress = feeManager.i_nativeAddress();

        (Common.Asset memory fee, , ) = feeManager.getFeeAndReward(
            address(this),
            reportData,
            feeTokenAddress
        );

        // Approve rewardManager to spend this contract's balance in fees
        IERC20(feeTokenAddress).approve(address(rewardManager), fee.amount);

        // Verify the report
        bytes memory verifiedReportData = IVerifierProxy(dsVerifyProxy).verify(
            unverifiedReport,
            abi.encode(feeTokenAddress)
        );

        Report memory verifiedReport = abi.decode(verifiedReportData, (Report));
        return verifiedReport;
    }

    function getEmptyReport() private pure returns (Report memory) {
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
        return emptyReport;
    }

    function newPriceSource(
        string memory name,
        address _chainlinkFeed,
        bytes32 _DSFeedId,
        uint256 _feedDecimalCorrection,
        uint256 _DSDecimalCorrection,
        uint256 _heartBeat
    ) public onlyOwner {
        bytes32 key = nameToKey(name);
        require(
            bytes(priceSourcesMap[key].name).length == 0,
            "NAME_ALREADY_EXIST"
        );
        registeredNames.push(name);

        Report memory emptyReport = getEmptyReport();

        priceSourcesMap[key] = PriceSources({
            chainlinkFeed: IChainlink(_chainlinkFeed),
            feedDecimalsCorrection: 10 ** _feedDecimalCorrection,
            lastDSReport: emptyReport,
            DSFeedId: _DSFeedId,
            DSRoundId: 0,
            DSDecimalCorrection: 10 ** _DSDecimalCorrection,
            heartBeat: _heartBeat,
            name: name
        });
    }

    function resetPriceSource(
        string memory name,
        address _chainlinkFeed,
        bytes32 _DSFeedId,
        uint256 _feedDecimalCorrection,
        uint256 _DSDecimalCorrection,
        uint256 _heartBeat,
        bool _resetReport
    ) public onlyOwner {
        bytes32 key = nameToKey(name);
        require(bytes(priceSourcesMap[key].name).length > 0, "NAME_NOT_EXIST");
        PriceSources storage priceSources = priceSourcesMap[key];
        priceSources.chainlinkFeed = IChainlink(_chainlinkFeed);
        priceSources.DSFeedId = _DSFeedId;
        priceSources.feedDecimalsCorrection = 10 ** _feedDecimalCorrection;
        priceSources.DSDecimalCorrection = 10 ** _DSDecimalCorrection;
        priceSources.heartBeat = _heartBeat;
        if (_resetReport) {
            priceSources.lastDSReport = getEmptyReport();
        }
    }

    function verifyReports(
        string[] memory names,
        bytes[] memory unverifiedReports
    ) public onlyOwner {
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = nameToKey(names[i]);
            PriceSources storage priceSources = priceSourcesMap[key];
            priceSources.lastDSReport = _verifyReport(unverifiedReports[i]);
            require(
                priceSources.lastDSReport.feedId == priceSources.DSFeedId,
                "DS_FEED_ID_NOT_MATCH"
            );
            priceSources.DSRoundId += 1;
            emit AnswerUpdated(
                int256(priceSources.lastDSReport.price),
                priceSources.lastDSReport.feedId,
                priceSources.DSRoundId,
                block.timestamp,
                names[i]
            );
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
        bytes32 key = nameToKey(name);
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
        require(
            DSReport.validFromTimestamp > 0 || feedUpdatedAt > 0,
            "NO_VALID_DATA"
        );
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

    function getAllPrices()
        public
        view
        returns (string[] memory names, uint256[] memory prices)
    {
        names = registeredNames;
        prices = new uint256[](registeredNames.length);
        for (uint256 i = 0; i < registeredNames.length; i++) {
            try this.getPriceByName(registeredNames[i]) returns (
                uint256 price
            ) {
                prices[i] = price;
            } catch {
                prices[i] = 0;
            }
        }
    }

    function getReportByName(string memory name) public view returns (Report memory) {
        bytes32 key = nameToKey(name);
        return priceSourcesMap[key].lastDSReport;
    }
}

contract ChainlinkDSAdaptor {
    address portal;
    bytes32 key;

    constructor(string memory tradingPairName, address _portal) {
        portal = _portal;
        key = keccak256(abi.encodePacked(tradingPairName));
    }

    function getMarkPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }

    function getAssetPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }
}