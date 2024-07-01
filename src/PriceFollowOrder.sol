/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "./libraries/Types.sol";
import "./libraries/Trading.sol";
import "./libraries/SignedDecimalMath.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/IPerpetual.sol";
import "./interfaces/internal/IPriceSource.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceFollowingOrder is Ownable {

    using SignedDecimalMath for int256;
    
    int256 public maxLeverage;
    address public jojoDealer;
    mapping(address => address) marketPriceSource;

    // Function to encode Order struct into bytes
    function encodeOrder(Types.Order memory order) public pure returns (bytes memory) {
        return abi.encode(order.perp, order.signer, order.paperAmount, order.creditAmount, order.info);
    }

    // Function to decode bytes back into Order struct
    function decodeOrder(bytes memory data) public pure returns (Types.Order memory) {
        (address perp, address signer, int128 paperAmount, int128 creditAmount, bytes32 info) =
            abi.decode(data, (address, address, int128, int128, bytes32));
        return Types.Order(perp, signer, paperAmount, creditAmount, info);
    }

    function setMaxleverage(int256 _maxLeverage) external {
        maxLeverage = _maxLeverage;
    }

    function withdraw(uint256 primaryAmount, uint256 secondaryAmount, bytes memory param) external onlyOwner {
        IDealer(jojoDealer).fastWithdraw(address(this), owner(), primaryAmount, secondaryAmount, false, param);
    }

    function isValidSignature(bytes32 hash, bytes calldata data) public view returns (bytes4 magicValue) {
        Types.Order memory order = decodeOrder(data);
        require(hash == Trading._structHash(order));
        // check price
        uint256 oraclePrice = IPriceSource(marketPriceSource[order.perp]).getMarkPrice();
        uint256 orderPrice = int256(order.creditAmount * 1e18 / order.paperAmount).abs();
        if (order.paperAmount >= 0) {
            require(orderPrice <= oraclePrice, "price is not fill");
        } else {
            require(orderPrice >= oraclePrice, "price is not fill");
        }
        // check margin
        (int256 netValue, uint256 exposure,,) = IDealer(jojoDealer).getTraderRisk(address(this));
        (int256 singleMarketExposure,) = IPerpetual(order.perp).balanceOf(address(this));
        int256 exposureChange = int256((singleMarketExposure + order.paperAmount).abs() - singleMarketExposure.abs())
            * SafeCast.toInt256(IDealer(jojoDealer).getMarkPrice(order.perp)) / 1e18;

        int256 exposureAfterTrade = SafeCast.toInt256(exposure) + exposureChange;
        require(exposureAfterTrade * 1e18 / netValue <= maxLeverage, "leverage is not fill");
        return 0x1626ba7e;
    }
}
