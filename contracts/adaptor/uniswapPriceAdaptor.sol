/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./emergencyOracle.sol";
import "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";


contract UniswapPriceAdaptor is Ownable{

    IStaticOracle public immutable UNISWAP_V3_ORACLE;
    uint8 public immutable decimal;
    address public immutable baseToken;
    address public immutable quoteToken;
    // query pools
    address[] public pools;
    // query period
    uint32 public period;
    address public priceFeedOracle;
    uint256 public impact;


    event UpdatePools(address[] oldPools, address[] newPools);
    event UpdatePeriod(uint32 oldPeriod, uint32 newPeriod);

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

    function getMarkPrice() external view returns (uint256) {
        uint256 uniswapPriceFeed = IStaticOracle(UNISWAP_V3_ORACLE).quoteSpecificPoolsWithTimePeriod(uint128(10**decimal), baseToken, quoteToken, pools, period);
        uint256 JOJOPriceFeed = EmergencyOracle(priceFeedOracle).getMarkPrice();
        uint256 diff = JOJOPriceFeed >= uniswapPriceFeed ? JOJOPriceFeed - uniswapPriceFeed : uniswapPriceFeed - JOJOPriceFeed;
        require(diff * 1e18 / JOJOPriceFeed <= impact, "deviation is too big");
        return uniswapPriceFeed;
    }

    function updatePools(address[] memory newPools) external onlyOwner{
        emit UpdatePools(pools, newPools);
        pools = newPools;
    }

    function updatePeriod(uint32 newPeriod) external onlyOwner {
        emit UpdatePeriod(period, newPeriod);
        period = newPeriod;
    }

    function updateImpact(uint32 newImpact) external onlyOwner {
        impact = newImpact;
    }
}
