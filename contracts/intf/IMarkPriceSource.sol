pragma solidity 0.8.9;

// return mark price

interface IMarkPriceSource {
    function getMarkPrice()
        external
        returns (
            uint256 price,
            uint128 updatedAt,
            bool heartbeatFailed
        );
}
