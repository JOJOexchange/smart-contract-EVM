pragma solidity 0.8.12;

interface ITradingProxy {
    function isValidPerpetualOperator(address o) external returns (bool);
}
