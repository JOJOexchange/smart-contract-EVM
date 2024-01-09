/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/FlashLoanReentrancyGuard.sol";
import "./libraries/SignedDecimalMath.sol";
import "./libraries/Types.sol";

abstract contract JUSDBankStorage is Ownable, ReentrancyGuard, FlashLoanReentrancyGuard {
    using SignedDecimalMath for uint256;

    // reserves amount
    uint256 public reservesNum;
    // max reserves amount
    uint256 public maxReservesNum;
    // max borrow JUSD amount per account
    uint256 public maxPerAccountBorrowAmount;
    // max total borrow JUSD amount
    uint256 public maxTotalBorrowAmount;
    // t0 total borrow JUSD amount
    uint256 public t0TotalBorrowAmount;
    // borrow fee rate
    uint256 public borrowFeeRate;
    // t0Rate
    uint256 public tRate;
    // update timestamp
    uint256 public lastUpdateTimestamp;

    bool public isLiquidatorWhitelistOpen;
    // insurance account
    address public insurance;
    // JUSD address
    address public JUSD;
    // primary address
    address public primaryAsset;

    address public JOJODealer;
    // reserves's list
    address[] public reservesList;
    mapping(address => bool) isLiquidatorWhiteList;
    // reserve token address ==> reserve info
    mapping(address => Types.ReserveInfo) public reserveInfo;
    // reserve token address ==> user info
    mapping(address => Types.UserInfo) public userInfo;
    // client -> operator -> bool
    mapping(address => mapping(address => bool)) public operatorRegistry;

    function accrueRate() public {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp == lastUpdateTimestamp) {
            return;
        }
        uint256 timeDifference = block.timestamp - uint256(lastUpdateTimestamp);
        tRate = tRate.decimalMul((timeDifference * borrowFeeRate) / Types.SECONDS_PER_YEAR + 1e18);
        lastUpdateTimestamp = currentTimestamp;
    }

    function getTRate() public view returns (uint256) {
        uint256 timeDifference = block.timestamp - uint256(lastUpdateTimestamp);
        return tRate + (borrowFeeRate * timeDifference) / Types.SECONDS_PER_YEAR;
    }
}
