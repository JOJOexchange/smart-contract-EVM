/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./EmergencyOracle.sol";

interface IStaticOracle {
    /// @notice Returns a quote, based on the given tokens and amount, by querying only the specified pools
    /// @dev Will revert if one of the pools is not prepared/configured correctly for the given period
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @param pools The pools to consider when calculating the quote
    /// @param period Number of seconds from which to calculate the TWAP
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function quoteSpecificPoolsWithTimePeriod(
        uint128 baseAmount,
        address baseToken,
        address quoteToken,
        address[] calldata pools,
        uint32 period
    )
        external
        view
        returns (uint256 quoteAmount);
}

contract UniswapPriceAdaptor is Ownable {
    IStaticOracle public immutable UNISWAP_V3_ORACLE;
    address public immutable baseToken;
    address public immutable quoteToken;
    address public priceFeedOracle;
    uint256 public impact;
    uint32 public period;
    uint8 public decimal;
    address[] public pools;

    event UpdatePools(address[] oldPools, address[] newPools);
    event UpdatePeriod(uint32 oldPeriod, uint32 newPeriod);
    event UpdateImpact(uint256 oldImpact, uint256 newImpact);

    constructor(
        address _uniswapAdaptor,
        uint8 _decimal,
        address _baseToken,
        address _quoteToken,
        address[] memory _pools,
        uint32 _period,
        address _priceFeedOracle,
        uint256 _impact
    ) {
        UNISWAP_V3_ORACLE = IStaticOracle(_uniswapAdaptor);
        decimal = _decimal;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        pools = _pools;
        period = _period;
        priceFeedOracle = _priceFeedOracle;
        impact = _impact;
    }

    function getPrice() internal view returns (uint256) {
        uint256 uniswapPriceFeed = IStaticOracle(UNISWAP_V3_ORACLE).quoteSpecificPoolsWithTimePeriod(
            uint128(10 ** decimal), baseToken, quoteToken, pools, period
        );
        uint256 jojoPriceFeed = EmergencyOracle(priceFeedOracle).getMarkPrice();
        uint256 diff =
            jojoPriceFeed >= uniswapPriceFeed ? jojoPriceFeed - uniswapPriceFeed : uniswapPriceFeed - jojoPriceFeed;
        require((diff * 1e18) / jojoPriceFeed <= impact, "deviation is too big");
        return uniswapPriceFeed;
    }

    function getMarkPrice() external view returns (uint256 price) {
        price = getPrice();
    }

    function getAssetPrice() external view returns (uint256 price) {
        price = getPrice();
    }

    function updatePools(address[] memory newPools) external onlyOwner {
        emit UpdatePools(pools, newPools);
        pools = newPools;
    }

    function updatePeriod(uint32 newPeriod) external onlyOwner {
        emit UpdatePeriod(period, newPeriod);
        period = newPeriod;
    }

    function updateImpact(uint256 newImpact) external onlyOwner {
        emit UpdateImpact(impact, newImpact);
        impact = newImpact;
    }
}
