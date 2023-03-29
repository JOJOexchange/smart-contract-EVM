/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";


contract UniswapPriceAdaptor {
    address public immutable uniswapAdaptor;
    uint8 public immutable decimal;
    address public immutable baseToken;
    address public immutable quoteToken;
    address[] public pools;
    uint32 public immutable period;

    constructor(
        address _uniswapAdaptor,
        uint8 _decimal,
        address _baseToken,
        address _quoteToken,
        address[] memory _pools,
        uint32 _period
    ) {
        uniswapAdaptor = _uniswapAdaptor;
        decimal = _decimal;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        pools = _pools;
        period = _period;
    }

    function getMarkPrice() external view returns (uint256) {
        return IStaticOracle(uniswapAdaptor).quoteSpecificPoolsWithTimePeriod(uint128(10**decimal), baseToken, quoteToken, pools, period);
    }
}
