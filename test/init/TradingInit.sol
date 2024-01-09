/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/Test.sol";
import "../../src/JOJODealer.sol";
import "../../src/libraries/Types.sol";
import "../../src/Perpetual.sol";
import "../../src/support/TestERC20.sol";
import "../../src/support/TestMarkPriceSource.sol";
import "../utils/EIP712Test.sol";
import "../utils/Utils.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

contract TradingInit is Test {
    // add this to be excluded from coverage report
    function test() public { }

    Cheats internal constant cheats = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    TestERC20 public jusd;
    TestERC20 public usdc;
    JOJODealer public jojoDealer;
    Utils internal utils;
    Perpetual[] internal perpList;
    TestMarkPriceSource[] internal priceSourceList;

    address[] internal traders;
    address public insurance;
    address payable[] internal users;
    uint256[] internal tradersKey;

    function initUsers() public {
        utils = new Utils();
        users = utils.createUsers(5);
        insurance = users[0];
        vm.label(insurance, "insurance");

        traders = new address[](3);
        tradersKey = new uint256[](3);
        tradersKey[0] = 0xA11CE;
        tradersKey[1] = 0xB0B;
        tradersKey[2] = 0xC0C;

        for (uint256 i; i < traders.length; i++) {
            traders[i] = vm.addr(tradersKey[i]);
        }
    }

    function initJOJODealer() public {
        jojoDealer.setMaxPositionAmount(10);
        jojoDealer.setOrderSender(address(this), true);
        for (uint256 i = 0; i < 2; i++) {
            Perpetual perp = new Perpetual(address(jojoDealer));
            TestMarkPriceSource priceSource = new TestMarkPriceSource();
            perpList.push(perp);
            priceSourceList.push(priceSource);
        }
        // inital ETH
        Types.RiskParams memory paramETH = Types.RiskParams({
            initialMarginRatio: 1e17,
            liquidationThreshold: 5e16,
            liquidationPriceOff: 1e16,
            insuranceFeeRate: 2e16,
            markPriceSource: address(priceSourceList[1]),
            name: "ETH",
            isRegistered: true
        });
        // initial BTC
        Types.RiskParams memory paramBTC = Types.RiskParams({
            initialMarginRatio: 5e16,
            liquidationThreshold: 3e16,
            liquidationPriceOff: 1e16,
            insuranceFeeRate: 1e16,
            markPriceSource: address(priceSourceList[0]),
            name: "BTC",
            isRegistered: true
        });
        jojoDealer.setPerpRiskParams(address(perpList[0]), paramBTC);
        jojoDealer.setPerpRiskParams(address(perpList[1]), paramETH);
        jojoDealer.setSecondaryAsset(address(jusd));
        jojoDealer.setFundingRateKeeper(address(this));
        jojoDealer.setInsurance(insurance);
        int256[] memory rateList = new int256[](2);
        rateList[0] = int256(1e18);
        rateList[1] = int256(1e18);
        address[] memory t = new address[](2);
        t[0] = address(perpList[0]);
        t[1] = address(perpList[1]);
        // jojoDealer.updateFundingRate(t, rateList);
        for (uint256 i = 0; i < traders.length; i++) {
            usdc.mint(traders[i], 1_000_000e6);
            jusd.mint(traders[i], 1_000_000e6);
            vm.startPrank(traders[i]);
            usdc.approve(address(jojoDealer), 1_000_000e6);
            jusd.approve(address(jojoDealer), 1_000_000e6);
            vm.stopPrank();
        }
    }

    function buildOrder(
        address signer,
        uint256 privateKey,
        int128 paper,
        int128 credit,
        address perpetual
    )
        public
        view
        returns (Types.Order memory order, bytes memory signature)
    {
        int64 makerFeeRate = 1e14;
        int64 takerFeeRate = 5e14;
        bytes memory infoBytes =
            abi.encodePacked(makerFeeRate, takerFeeRate, uint64(block.timestamp), uint64(block.timestamp));
        order = Types.Order({
            perp: perpetual,
            signer: signer,
            paperAmount: paper,
            creditAmount: credit,
            info: bytes32(infoBytes)
        });
        bytes32 domainSeparator = EIP712Test._buildDomainSeparator("JOJO", "1", address(jojoDealer));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, EIP712Test._structHash(order)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function constructTradeData(
        int128 takerAmount,
        int128 takerCredit,
        int128 makerAmount,
        int128 makerCredit,
        uint256 matchPaperAmount1,
        uint256 matchPaperAmount2,
        address perpetual
    )
        internal
        view
        returns (bytes memory)
    {
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(traders[0], tradersKey[0], takerAmount, takerCredit, perpetual);
        (Types.Order memory order2, bytes memory signature2) =
            buildOrder(traders[1], tradersKey[1], makerAmount, makerCredit, perpetual);
        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = order1;
        orderList[1] = order2;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = signature1;
        signatureList[1] = signature2;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = matchPaperAmount1;
        matchPaperAmount[1] = matchPaperAmount2;
        return abi.encode(orderList, signatureList, matchPaperAmount);
    }

    function trade(
        int128 takerAmount,
        int128 takerCredit,
        int128 makerAmount,
        int128 makerCredit,
        uint256 matchPaperAmount1,
        uint256 matchPaperAmount2,
        address perpetual
    )
        public
    {
        bytes memory tradeData = constructTradeData(
            takerAmount, takerCredit, makerAmount, makerCredit, matchPaperAmount1, matchPaperAmount2, perpetual
        );
        Perpetual(perpetual).trade(tradeData);
    }

    function setUp() public {
        jusd = new TestERC20("JUSD", "JUSD", 6);
        usdc = new TestERC20("USDC", "USDC", 6);
        initUsers();
        jojoDealer = new JOJODealer(address(usdc));
        initJOJODealer();
        priceSourceList[0].setMarkPrice(30_000e6);
        priceSourceList[1].setMarkPrice(2000e6);
    }
}
