pragma solidity 0.8.9;

interface ITradingProxy {
    function isValidPerpetualOperator(address o) external returns (bool);
}
