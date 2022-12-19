/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice emergency fallback oracle.
/// Using when the third party oracle is not available.
contract EmergencyOracle is Ownable{
    uint256 public price;
    uint256 public roundId;
    string public description;

    // Align with chainlink
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    constructor(address _owner, string memory _description) Ownable() {
        transferOwnership(_owner);
        description = _description;
    }

    function getMarkPrice() external view returns (uint256) {
        return price;
    }

    function setMarkPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit AnswerUpdated(SafeCast.toInt256(price), roundId, block.timestamp);
        roundId += 1;
    }
}

contract EmergencyOracleFactory {
    event NewEmergencyOracle(address owner, address newOracle);

    function newEmergencyOracle(string calldata description) external {
        address newOracle = address(
            new EmergencyOracle(msg.sender, description)
        );
        emit NewEmergencyOracle(msg.sender, newOracle);
    }
}
