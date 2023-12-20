pragma solidity ^0.8.0;

contract MockUniswapOracle {


    function quoteSpecificPoolsWithTimePeriod(
        uint128 baseAmount,
        address baseToken,
        address quoteToken,
        address[] calldata pools,
        uint32 period
    ) external view returns (uint256 quoteAmount){
        return 949999;
    }
}