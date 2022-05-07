/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

interface IChainlink {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestAnswer() external view returns (int256 answer);
}

contract ChainlinkExpandAdaptor {
    address public immutable chainlink;
    uint256 public immutable decimalsCorrection;
    int256 public immutable heartbeat;

    constructor(
        address _chainlink,
        uint256 _decimalsCorrection,
        int256 _heartbeat
    ) {
        chainlink = _chainlink;
        decimalsCorrection = 10**_decimalsCorrection;
        heartbeat = _heartbeat;
    }

    function getMarkPrice() external view returns (uint256) {
        return
            (uint256(IChainlink(chainlink).latestAnswer()) * 1e18) /
            decimalsCorrection;
    }
}
