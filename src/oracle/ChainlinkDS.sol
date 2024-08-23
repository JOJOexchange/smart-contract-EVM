/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/llo-feeds/interfaces/IVerifierFeeManager.sol";
import "../interfaces/internal/IChainlink.sol";

//Inherit from https://docs.chain.link/data-streams/tutorials/streams-direct/streams-direct-onchain-verification
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

//Inherit from https://docs.chain.link/data-streams/tutorials/streams-direct/streams-direct-onchain-verification
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

//Inherit from https://docs.chain.link/data-streams/tutorials/streams-direct/streams-direct-onchain-verification
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

/**
 * @title PriceSources
 * @dev Struct to store information about price sources.
 * This struct holds various details about a price source, including the Chainlink feed,
 * decimal corrections, the last data stream report, and heartbeat intervals.
 * DecimalsCorrection is used to adjust the decimal of Chainlink's price data to the decimal required by JOJO.
 * This process is achieved through price * 1e18 / DecimalsCorrection.
 * So, if we want to increase the decimal by 6 places, we should set DecimalsCorrection to 1e12.
 * If we want to decrease the decimal by 12 places, we should set DecimalsCorrection to 1e30.
 */
struct PriceSources {
    IChainlink chainlinkFeed; // The Chainlink feed interface for fetching price data
    uint256 feedDecimalsCorrection; // Decimal correction factor for the Chainlink feed price
    Report lastDSReport; // The last verified data stream report
    bytes32 DSFeedId; // The feed ID for the data stream
    uint256 DSRoundId; // The round ID for the data stream
    uint256 DSDecimalCorrection; // Decimal correction factor for the data stream price
    uint256 heartBeat; // Heartbeat interval to ensure data freshness
    address adaptor; // The address of the ChainlinkDSAdaptor, which is registered in JOJODealer
    string name; // The name of the price source
}

/**
 * @title ChainlinkDSPortal
 * @dev This contract manages the Chainlink Data Stream Portal.
 * This contract will manage the prices of multiple trading pairs, each with two price sources: chainlink feed and chainlink datastream. When querying prices, it will return the more recent one from these two sources..
 * Only owner can add new price sources and verify reports.
 */
contract ChainlinkDSPortal is Ownable {
    // chainlink datastream proxy
    IVerifierProxy public immutable dsVerifyProxy;
    address public reportSubmitter;

    // registered sources
    string[] public registeredNames;
    mapping(bytes32 => PriceSources) public priceSourcesMap;

    // The prices from pricesources are all calculated in USD, and the price of USDC needs to be considered as well, using Chainlink's USDC price.
    uint256 public immutable usdcHeartbeat;
    address public immutable usdcSource;

    /**
     * @dev Emitted when a new report is verified.
     * @param current The current price.
     * @param feedID The feed ID.
     * @param roundId The round ID.
     * @param updatedAt The timestamp when the answer was updated.
     * @param name The name of the price source.
     */
    event AnswerUpdated(
        int256 indexed current,
        bytes32 indexed feedID,
        uint256 indexed roundId,
        uint256 updatedAt,
        string name
    );

    /**
     * @dev Constructor to initialize the contract state.
     * @param _dsVerifyProxy The address of the Data Stream verification proxy.
     * @param _usdcHeartbeat The heartbeat interval for USDC.
     * @param _usdcSource The address of the USDC data source.
     */
    constructor(
        address _dsVerifyProxy,
        address _reportSubmitter,
        uint256 _usdcHeartbeat,
        address _usdcSource
    ) {
        dsVerifyProxy = IVerifierProxy(_dsVerifyProxy);
        reportSubmitter = _reportSubmitter;
        usdcHeartbeat = _usdcHeartbeat;
        usdcSource = _usdcSource;
    }

    /**
     * @dev Modifier to restrict access to the owner or the report submitter.
     */
    modifier onlyOwnerOrReportSubmitter() {
        require(
            msg.sender == owner() || msg.sender == reportSubmitter,
            "Not authorized"
        );
        _;
    }

    /**
     * @dev Converts a name to a unique key using keccak256 hash.
     * @param name The name to be converted.
     * @return key The unique key.
     */
    function nameToKey(string memory name) public pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(name));
    }

    /**
     * @dev Allows the owner to set the report submitter address.
     * @param _reportSubmitter The address to be set as the report submitter.
     */
    function setReportSubmitter(address _reportSubmitter) external onlyOwner {
        reportSubmitter = _reportSubmitter;
    }

    /**
     * @dev Verifies a report.
     * @param unverifiedReport The raw report to be verified.
     * @return verifiedReport The verified report.
     */
    function _verifyReport(
        bytes memory unverifiedReport
    ) private returns (Report memory verifiedReport) {
        // Report verification fees, paid in Native token
        IFeeManager feeManager = IFeeManager(
            address(dsVerifyProxy.s_feeManager())
        );

        (, /* bytes32[3] reportContextData */ bytes memory reportData) = abi
            .decode(unverifiedReport, (bytes32[3], bytes));

        address feeTokenAddress = feeManager.i_nativeAddress();

        (Common.Asset memory fee, , ) = feeManager.getFeeAndReward(
            address(this),
            reportData,
            feeTokenAddress
        );

        // Approve feeManager to spend this contract's balance in fees
        IERC20(feeTokenAddress).approve(address(feeManager), fee.amount);

        // Verify the report
        bytes memory verifiedReportData = IVerifierProxy(dsVerifyProxy).verify(
            unverifiedReport,
            abi.encode(feeTokenAddress)
        );

        verifiedReport = abi.decode(verifiedReportData, (Report));
    }

    /**
     * @dev Returns an empty report.
     * @return emptyReport The empty report.
     */
    function _getEmptyReport()
        private
        pure
        returns (Report memory emptyReport)
    {
        emptyReport = Report({
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
    }

    /**
     * @dev Adds a new price source.
     * @param name The name of the price source.
     * @param _chainlinkFeed The address of the Chainlink feed.
     * @param _DSFeedId The Data Stream feed ID.
     * @param _feedDecimalCorrection The decimal correction for the feed.
     * @param _DSDecimalCorrection The decimal correction for the Data Stream.
     * @param _heartBeat The heartbeat interval for the price source.
     */
    function newPriceSources(
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
        address adaptor = address(new ChainlinkDSAdaptor(name, address(this)));
        Report memory emptyReport = _getEmptyReport();

        priceSourcesMap[key] = PriceSources({
            chainlinkFeed: IChainlink(_chainlinkFeed),
            feedDecimalsCorrection: 10 ** _feedDecimalCorrection,
            lastDSReport: emptyReport,
            DSFeedId: _DSFeedId,
            DSRoundId: 0,
            DSDecimalCorrection: 10 ** _DSDecimalCorrection,
            heartBeat: _heartBeat,
            adaptor: adaptor,
            name: name
        });
    }

    /**
     * @dev Resets an existing price source.
     * @param name The name of the price source.
     * @param _chainlinkFeed The address of the Chainlink feed.
     * @param _DSFeedId The Data Stream feed ID.
     * @param _feedDecimalCorrection The decimal correction for the feed.
     * @param _DSDecimalCorrection The decimal correction for the Data Stream.
     * @param _heartBeat The heartbeat interval for the price source.
     * @param _resetReport Whether to reset the last report.
     */
    function resetPriceSources(
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
            priceSources.lastDSReport = _getEmptyReport();
        }
    }

    /**
     * @dev Verifies multiple reports.
     * @param names The names of the price sources.
     * @param unverifiedReports The reports to be verified.
     */
    function verifyReports(
        string[] memory names,
        bytes[] memory unverifiedReports
    ) public onlyOwnerOrReportSubmitter {
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 key = nameToKey(names[i]);
            PriceSources storage priceSources = priceSourcesMap[key];
            Report memory newReport = _verifyReport(unverifiedReports[i]);
            require(
                newReport.validFromTimestamp >
                    priceSources.lastDSReport.validFromTimestamp,
                "INVALID_REPORT_TIMESTAMP"
            );
            require(
                newReport.feedId == priceSources.DSFeedId,
                "DS_FEED_ID_NOT_MATCH"
            );
            priceSources.lastDSReport = _verifyReport(unverifiedReports[i]);
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

    function getRawUSDCPrice() public view returns (uint256) {
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
        return getPriceByKey(nameToKey(name));
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

        return (price * 1e8) / getRawUSDCPrice();
    }

    function getAllPrices()
        public
        view
        returns (
            string[] memory names,
            uint256[] memory prices,
            uint256 rawUSDCPrice
        )
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
        rawUSDCPrice = getRawUSDCPrice();
    }

    function getReportByName(
        string memory name
    ) public view returns (Report memory) {
        bytes32 key = nameToKey(name);
        return priceSourcesMap[key].lastDSReport;
    }

    function getPriceSourcesByName(
        string memory name
    ) public view returns (PriceSources memory) {
        bytes32 key = nameToKey(name);
        return priceSourcesMap[key];
    }
}

/**
 * @title ChainlinkDSAdaptor
 * @dev This contract adapts the Chainlink Data Stream Portal for specific trading pairs.
 * This contract is directly registered in JOJODealer.
 */
contract ChainlinkDSAdaptor {
    address portal;
    bytes32 key;

    /**
     * @dev Constructor to initialize the adaptor.
     * @param _tradingPairName The name of the trading pair.
     * @param _portal The address of the Chainlink Data Stream Portal.
     */
    constructor(string memory _tradingPairName, address _portal) {
        portal = _portal;
        key = keccak256(abi.encodePacked(_tradingPairName));
    }

    function getMarkPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }

    function getAssetPrice() external view returns (uint256) {
        return ChainlinkDSPortal(portal).getPriceByKey(key);
    }
}
