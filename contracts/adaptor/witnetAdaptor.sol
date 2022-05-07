/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

// BTC 0x24beead4
// ETH 0x3d15f701

interface IERC2362
{
	/**
	 * @dev Exposed function pertaining to EIP standards
	 * @param _id bytes32 ID of the query
	 * @return int,uint,uint returns the value, timestamp, and status code of query
	 */
	function valueFor(bytes32 _id) external view returns(int256,uint256,uint256);
}

contract WitnetAdaptor{
    address public witnet;
    bytes32 public id;

    constructor(address _witnet, bytes32 _id) {
        witnet = _witnet;
        id = _id;
    }

    function getMarkPrice() external view returns (uint256 price) {
        (int256 lastPrice,,)=IERC2362(witnet).valueFor(id);
        price = uint256(lastPrice);
    }
}