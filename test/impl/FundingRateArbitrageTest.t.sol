/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/Test.sol";
import "../../src/FundingRateArbitrage.sol";
import "../../src/JUSDBank.sol";
import "../../src/JOJODealer.sol";
import "../../src/Perpetual.sol";
import "../../src/libraries/Types.sol";
import "../../src/oracle/EmergencyOracle.sol";
import "../../src/support/MockSwap.sol";
import "../../src/support/TestERC20.sol";
import "../../src/support/HelperContract.sol";
import "../utils/EIP712Test.sol";
import "../utils/Utils.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

// Check fundingRateArbitrage
contract FundingRateArbitrageTest is Test {
    Cheats internal constant cheats = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    FundingRateArbitrage public fundingRateArbitrage;
    Utils internal utils;
    TestERC20 public eth;
    JUSDBank public jusdBank;
    TestERC20 public jusd;
    TestERC20 public USDC;
    Perpetual public perpetual;
    EmergencyOracle public ETHOracle;
    JOJODealer public jojoDealer;
    MockSwap public swapContract;

    address payable[] internal users;
    address internal alice;
    address internal bob;
    address internal insurance;
    address internal operator;
    address internal Owner;
    address internal orderSender;
    address internal fastWithdraw;

    address internal sender1;
    address internal sender2;
    address internal sender3;

    uint256 internal sender1PrivateKey;
    uint256 internal sender2PrivateKey;
    uint256 internal sender3PrivateKey;

    function initUsers() public {
        // users
        utils = new Utils();
        users = utils.createUsers(10);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        insurance = users[2];
        vm.label(insurance, "Insurance");
        operator = users[3];
        vm.label(operator, "operator");
        Owner = users[4];
        vm.label(Owner, "Owner");
        orderSender = users[5];
        vm.label(orderSender, "orderSender");
        fastWithdraw = users[6];
        vm.label(fastWithdraw, "fastWithdraw");

        sender1PrivateKey = 0xA11CE;
        sender2PrivateKey = 0xB0B;
        sender3PrivateKey = 0xC0C;

        sender1 = vm.addr(sender1PrivateKey);
        sender2 = vm.addr(sender2PrivateKey);
        sender3 = vm.addr(sender3PrivateKey);
    }

    function initJUSDBank() public {
        //bank
        jusdBank = new JUSDBank(
            // maxReservesAmount_
            10,
            insurance,
            address(jusd),
            address(jojoDealer),
            // maxBorrowAmountPerAccount_
            100_000_000_000,
            // maxBorrowAmount_
            100_000_000_001,
            // borrowFeeRate_
            0,
            address(USDC)
        );

        jusdBank.initReserve(
            // token
            address(eth),
            // initialMortgageRate
            8e17,
            // maxDepositAmount
            4000e18,
            // maxDepositAmountPerAccount
            2030e18,
            // maxBorrowValue
            100_000e6,
            // liquidateMortgageRate
            825e15,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(ETHOracle)
        );

        jusd.mint(address(jusdBank), 100_000e6);
    }

    function initFundingRateSetting() public {
        fundingRateArbitrage = new FundingRateArbitrage(
            //  _collateral,
            address(eth),
            // _JOJODealer
            address(jojoDealer),
            // _perpMarket
            address(perpetual),
            // _Operator
            operator,
            address(ETHOracle)
        );

        fundingRateArbitrage.transferOwnership(Owner);
        vm.startPrank(Owner);
        fundingRateArbitrage.setOperator(sender1, true);
        fundingRateArbitrage.setMaxNetValue(10_000e6);
        fundingRateArbitrage.setDefaultQuota(10_000e6);
        vm.stopPrank();
    }

    function initJOJODealer() public {
        jojoDealer.setMaxPositionAmount(10);
        jojoDealer.setOrderSender(orderSender, true);
        jojoDealer.setWithdrawTimeLock(10);
        Types.RiskParams memory param = Types.RiskParams({
            initialMarginRatio: 5e16,
            liquidationThreshold: 3e16,
            liquidationPriceOff: 1e16,
            insuranceFeeRate: 2e16,
            markPriceSource: address(ETHOracle),
            name: "ETH",
            isRegistered: true
        });
        jojoDealer.setPerpRiskParams(address(perpetual), param);
        jojoDealer.setFastWithdrawalWhitelist(fastWithdraw, true);
        jojoDealer.setSecondaryAsset(address(jusd));
    }

    function initSupportSWAP() public {
        swapContract = new MockSwap(address(USDC), address(eth), address(ETHOracle));
        USDC.mint(address(swapContract), 100_000e6);
        eth.mint(address(swapContract), 10_000e18);
    }

    function setUp() public {
        eth = new TestERC20("eth", "eth", 18);
        jusd = new TestERC20("jusd", "jusd", 6);
        USDC = new TestERC20("usdc", "usdc", 6);
        ETHOracle = new EmergencyOracle("ETH Oracle");
        initUsers();
        jojoDealer = new JOJODealer(address(USDC));
        perpetual = new Perpetual(address(jojoDealer));
        initJOJODealer();
        initJUSDBank();
        initFundingRateSetting();
        initSupportSWAP();
        jusd.mint(address(this), 10_010e6);
        jusd.approve(address(jojoDealer), 10_010e6);
        jojoDealer.deposit(0, 10_010e6, address(fundingRateArbitrage));
        ETHOracle.setMarkPrice(1000e6);
    }

    function initAlice() public {
        USDC.mint(alice, 100e6);
        vm.startPrank(alice);
        USDC.approve(address(fundingRateArbitrage), 100e6);
    }

    function testDepositFromLP1() public {
        initAlice();
        cheats.expectRevert("deposit amount is zero");
        fundingRateArbitrage.deposit(0);
        vm.stopPrank();

        vm.startPrank(Owner);
        fundingRateArbitrage.setMaxNetValue(0);
        vm.stopPrank();

        vm.startPrank(alice);
        cheats.expectRevert("net value exceed limitation");
        fundingRateArbitrage.deposit(100e6);
        vm.stopPrank();

        vm.startPrank(Owner);
        fundingRateArbitrage.setMaxNetValue(10_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        fundingRateArbitrage.deposit(100e6);
        vm.stopPrank();
        assertEq(fundingRateArbitrage.getIndex(), 1e6);

        USDC.mint(bob, 100e6);
        vm.startPrank(bob);
        USDC.approve(address(fundingRateArbitrage), 100e6);
        fundingRateArbitrage.deposit(100e6);
        vm.stopPrank();
        assertEq(fundingRateArbitrage.getIndex(), 1e6);
    }

    function testDepositAndDonate() public {
        vm.startPrank(Owner);

        fundingRateArbitrage.setMaxNetValue(100_000e6);
        initAlice();
        USDC.mint(alice, 1000e6);
        fundingRateArbitrage.deposit(1);
        USDC.transfer(address(fundingRateArbitrage), 1000e6);
        vm.stopPrank();

        USDC.mint(bob, 1000e6);
        vm.startPrank(bob);
        USDC.approve(address(fundingRateArbitrage), 1000e6);
        fundingRateArbitrage.deposit(1000e6);

        fundingRateArbitrage.approve(address(fundingRateArbitrage), 1_999_999_996_000);
        uint256 index = fundingRateArbitrage.requestWithdraw(1_999_999_996_000);
        vm.stopPrank();

        vm.startPrank(Owner);
        uint256[] memory indexs = new uint256[](1);
        indexs[0] = index;
        fundingRateArbitrage.permitWithdrawRequests(indexs);
    }

    function testDepositAndToPerp() public {
        vm.startPrank(Owner);
        fundingRateArbitrage.setDepositFeeRate(1e16);
        jusd.mint(Owner, 1000e6);
        jusd.approve(address(jojoDealer), 1000e6);
        jojoDealer.deposit(0, 1000e6, address(fundingRateArbitrage));
        assertEq(fundingRateArbitrage.depositFeeRate(), 1e16);

        initAlice();
        fundingRateArbitrage.deposit(100e6);
        vm.stopPrank();
        assertEq(USDC.balanceOf(Owner), 1e6);
        vm.startPrank(Owner);
        fundingRateArbitrage.depositUSDCToPerp(50e6);
        fundingRateArbitrage.fastWithdrawUSDCFromPerp(50e6);
        fundingRateArbitrage.fastWithdrawJUSDFromPerp(1000e6);
        vm.stopPrank();
    }

    function testWithdrawFromLP1() public {
        vm.startPrank(Owner);
        fundingRateArbitrage.setWithdrawSettleFee(2e6);
        fundingRateArbitrage.setMinimumWithdraw(1e6);
        vm.stopPrank();

        initAlice();
        cheats.expectRevert("deposit amount is zero");
        fundingRateArbitrage.deposit(0);
        fundingRateArbitrage.deposit(100e6);

        fundingRateArbitrage.approve(address(fundingRateArbitrage), 1000e18);
        cheats.expectRevert("Withdraw amount is smaller than minimumWithdraw");
        fundingRateArbitrage.requestWithdraw(5e17);
        cheats.expectRevert("Withdraw amount is smaller than settleFee");
        fundingRateArbitrage.requestWithdraw(15e17);
        uint256 index = fundingRateArbitrage.requestWithdraw(100e18);
        vm.stopPrank();

        vm.startPrank(Owner);
        uint256[] memory indexs = new uint256[](1);
        indexs[0] = index;
        fundingRateArbitrage.permitWithdrawRequests(indexs);
        assertEq(USDC.balanceOf(alice), 98_000_000);
    }

    function testWithdrawFromLPWithRate() public {
        vm.startPrank(Owner);
        fundingRateArbitrage.setDepositFeeRate(1e16);
        fundingRateArbitrage.setWithdrawFeeRate(1e16);
        vm.stopPrank();

        initAlice();
        fundingRateArbitrage.deposit(100e6);
        fundingRateArbitrage.approve(address(fundingRateArbitrage), 99e18);
        uint256 index = fundingRateArbitrage.requestWithdraw(99e18);
        vm.stopPrank();

        vm.startPrank(Owner);
        uint256[] memory indexs = new uint256[](1);
        indexs[0] = index;
        fundingRateArbitrage.permitWithdrawRequests(indexs);
        cheats.expectRevert("request has been executed");
        fundingRateArbitrage.permitWithdrawRequests(indexs);

        assertEq(USDC.balanceOf(alice), 9801e4);
    }

    function buildOrder(
        address signer,
        uint256 privateKey,
        int128 paper,
        int128 credit
    )
        public
        view
        returns (Types.Order memory order, bytes memory signature)
    {
        int64 makerFeeRate = 2e14;
        int64 takerFeeRate = 7e14;

        bytes memory infoBytes =
            abi.encodePacked(makerFeeRate, takerFeeRate, uint64(block.timestamp), uint64(block.timestamp));

        order = Types.Order({
            perp: address(perpetual),
            signer: signer,
            paperAmount: paper,
            creditAmount: credit,
            info: bytes32(infoBytes)
        });

        bytes32 domainSeparator = EIP712Test._buildDomainSeparator("JOJO", "1", address(jojoDealer));
        bytes32 structHash = EIP712Test._structHash(order);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function constructTradeData() internal view returns (bytes memory) {
        (Types.Order memory order1, bytes memory signature1) = buildOrder(sender1, sender1PrivateKey, -2e18, 990e6);

        (Types.Order memory order2, bytes memory signature2) = buildOrder(sender2, sender2PrivateKey, 1e18, -1010e6);

        (Types.Order memory order3, bytes memory signature3) = buildOrder(sender3, sender3PrivateKey, 1e18, -1000e6);

        Types.Order[] memory orderList = new Types.Order[](3);
        orderList[0] = order1;
        orderList[1] = order2;
        orderList[2] = order3;
        bytes[] memory signatureList = new bytes[](3);
        signatureList[0] = signature1;
        signatureList[1] = signature2;
        signatureList[2] = signature3;
        uint256[] memory matchPaperAmount = new uint256[](3);
        matchPaperAmount[0] = 2e18;
        matchPaperAmount[1] = 1e18;
        matchPaperAmount[2] = 1e18;
        return abi.encode(orderList, signatureList, matchPaperAmount);
    }

    function testOpenNormalPositionTrade() public {
        vm.startPrank(sender1);
        USDC.mint(sender1, 15_000e6);
        USDC.approve(address(jojoDealer), 15_000e6);
        jojoDealer.deposit(5000e6, 0, sender1);
        jojoDealer.deposit(5000e6, 0, sender2);
        jojoDealer.deposit(5000e6, 0, sender3);
        vm.stopPrank();

        vm.startPrank(orderSender);
        bytes memory tradeData = constructTradeData();
        perpetual.trade(tradeData);
    }

    function constructTradeDataForPool(
        int128 order1Amount,
        int128 order1Credit,
        int128 order2Amount,
        int128 order2Credit
    )
        internal
        view
        returns (bytes memory)
    {
        (Types.Order memory order1, bytes memory signature1) =
            buildOrder(address(fundingRateArbitrage), sender1PrivateKey, order1Amount, order1Credit);

        (Types.Order memory order2, bytes memory signature2) =
            buildOrder(sender2, sender2PrivateKey, order2Amount, order2Credit);

        Types.Order[] memory orderList = new Types.Order[](2);
        orderList[0] = order1;
        orderList[1] = order2;
        bytes[] memory signatureList = new bytes[](2);
        signatureList[0] = signature1;
        signatureList[1] = signature2;
        uint256[] memory matchPaperAmount = new uint256[](2);
        matchPaperAmount[0] = 1e18;
        matchPaperAmount[1] = 1e18;
        return abi.encode(orderList, signatureList, matchPaperAmount);
    }

    function testDepositTwoToken() public {
        USDC.mint(alice, 3000e6);
        TestERC20 link = new TestERC20("link", "link", 18);
        link.mint(address(swapContract), 100e18);
        vm.startPrank(alice);
        USDC.approve(address(fundingRateArbitrage), 3000e6);
        fundingRateArbitrage.deposit(3000e6);
        vm.stopPrank();

        // open position
        vm.startPrank(Owner);

        uint256 minReceivedCollateral = 2e18;

        bytes memory swapData = swapContract.getSwapUSDCToOtherData(2400e6, address(eth));
        bytes memory spotTradeParam = abi.encode(address(swapContract), address(swapContract), 2400e6, swapData);

        fundingRateArbitrage.swapBuyToken(minReceivedCollateral, address(eth), spotTradeParam);

        cheats.expectRevert("collateral is not in the whitelist");
        fundingRateArbitrage.swapBuyToken(minReceivedCollateral, address(link), spotTradeParam);
        cheats.expectRevert("collateral is not in the whitelist");
        fundingRateArbitrage.swapSellToken(minReceivedCollateral, address(link), spotTradeParam);
        vm.stopPrank();

        EmergencyOracle linkOracle = new EmergencyOracle("Link Oracle");
        linkOracle.setMarkPrice(20e6);
        swapContract.addTokenPrice(address(link), address(linkOracle));
        vm.startPrank(Owner);
        fundingRateArbitrage.updateOracle(address(link), address(linkOracle));
        fundingRateArbitrage.addCollateral(address(link));
        address[] memory collateralList = fundingRateArbitrage.getCollateralList();
        uint256 price = fundingRateArbitrage.getCollateralPrice(address(link));
        assertEq(collateralList[1], address(link));
        assertEq(price, 20e6);
        uint256 minReceivedCollateral2 = 5e18;
        bytes memory swapData2 = swapContract.getSwapUSDCToOtherData(100e6, address(link));
        bytes memory spotTradeParam2 = abi.encode(address(swapContract), address(swapContract), 100e6, swapData2);
        fundingRateArbitrage.swapBuyToken(minReceivedCollateral2, address(link), spotTradeParam2);

        fundingRateArbitrage.removeCollateral(address(link));
        fundingRateArbitrage.updateOracle(address(link), address(0));
    }

    function testPoolOpenPosition() public {
        USDC.mint(alice, 2400e6);
        vm.startPrank(alice);
        USDC.approve(address(fundingRateArbitrage), 2400e6);
        fundingRateArbitrage.deposit(2400e6);
        vm.stopPrank();

        vm.startPrank(sender2);
        USDC.mint(sender2, 5000e6);
        USDC.approve(address(jojoDealer), 5000e6);
        jojoDealer.deposit(5000e6, 0, sender2);
        vm.stopPrank();

        // open position
        vm.startPrank(Owner);

        uint256 minReceivedCollateral = 2e18;

        bytes memory swapData = swapContract.getSwapUSDCToOtherData(2400e6, address(eth));
        bytes memory spotTradeParam = abi.encode(address(swapContract), address(swapContract), 2400e6, swapData);

        bytes memory tradeData = constructTradeDataForPool(-1e18, 990e6, 1e18, -1010e6);

        fundingRateArbitrage.swapBuyToken(minReceivedCollateral, address(eth), spotTradeParam);
        vm.stopPrank();

        vm.startPrank(orderSender);
        perpetual.trade(tradeData);

        (int256 paper, int256 credit) = perpetual.balanceOf(address(fundingRateArbitrage));
        console.logInt(paper);
        console.logInt(credit);
    }

    function testPoolClosePosition() public {
        USDC.mint(alice, 2000e6);
        vm.startPrank(alice);
        USDC.approve(address(fundingRateArbitrage), 2000e6);
        fundingRateArbitrage.deposit(2000e6);
        vm.stopPrank();

        vm.startPrank(sender2);
        USDC.mint(sender2, 5000e6);
        USDC.approve(address(jojoDealer), 5000e6);
        jojoDealer.deposit(5000e6, 0, sender2);
        vm.stopPrank();

        vm.startPrank(Owner);
        uint256 minReceivedCollateral = 3e18;
        bytes memory swapData = swapContract.getSwapUSDCToOtherData(2000e6, address(eth));
        bytes memory spotTradeParam = abi.encode(address(swapContract), address(swapContract), 2000e6, swapData);

        bytes memory tradeData = constructTradeDataForPool(-1e18, 990e6, 1e18, -1010e6);

        cheats.expectRevert("SWAP SLIPPAGE");
        fundingRateArbitrage.swapBuyToken(minReceivedCollateral, address(eth), spotTradeParam);
        minReceivedCollateral = 2e18;
        fundingRateArbitrage.swapBuyToken(minReceivedCollateral, address(eth), spotTradeParam);

        vm.stopPrank();

        vm.startPrank(orderSender);
        perpetual.trade(tradeData);

        (int256 paper, int256 credit) = perpetual.balanceOf(address(fundingRateArbitrage));
        console.logInt(paper);
        console.logInt(credit);

        // close position
        uint256 minReceivedUSDC = 2900e6;
        bytes memory swapData2 = swapContract.getSwapToUSDCData(2e18, address(eth));
        bytes memory spotTradeParam2 = abi.encode(address(swapContract), address(swapContract), 2e18, swapData2);

        bytes memory tradeData2 = constructTradeDataForPool(1e18, -1000e6, -1e18, 990e6);

        perpetual.trade(tradeData2);
        vm.stopPrank();

        vm.startPrank(Owner);

        cheats.expectRevert("SWAP SLIPPAGE");
        fundingRateArbitrage.swapSellToken(minReceivedUSDC, address(eth), spotTradeParam2);

        bytes memory spotTradeParam3 = abi.encode(address(swapContract), address(swapContract), 2e18, "swap()");
        cheats.expectRevert();
        fundingRateArbitrage.swapSellToken(minReceivedUSDC, address(eth), spotTradeParam3);

        minReceivedUSDC = 2000e6;
        fundingRateArbitrage.swapSellToken(minReceivedUSDC, address(eth), spotTradeParam2);

        vm.stopPrank();
    }

    function testBuildOrderParam() public view {
        bytes memory swapData2 = swapContract.getSwapToUSDCData(2e18, address(eth));
        fundingRateArbitrage.buildSpotSwapData(address(swapContract), address(swapContract), 2400e6, swapData2);
    }

    function testSetDepositFee() public {
        vm.startPrank(Owner);
        fundingRateArbitrage.setDepositFeeRate(1e16);
        assertEq(fundingRateArbitrage.depositFeeRate(), 1e16);
    }

    function testSetWithdrawSettleFee() public {
        vm.startPrank(Owner);
        fundingRateArbitrage.setWithdrawSettleFee(2e6);
        assertEq(fundingRateArbitrage.withdrawSettleFee(), 2e6);
    }

    function testDepositTooMuch() public {
        USDC.mint(alice, 10_000e6);
        vm.startPrank(Owner);
        fundingRateArbitrage.setMaxNetValue(10_010e6);
        vm.stopPrank();
        initAlice();
        USDC.approve(address(fundingRateArbitrage), 10_001e6);
        cheats.expectRevert("usdc amount bigger than quota");
        fundingRateArbitrage.deposit(10_001e6);
        vm.stopPrank();

        vm.startPrank(Owner);
        fundingRateArbitrage.setPersonalQuota(alice, 10_010e6);
        vm.stopPrank();
        vm.startPrank(alice);
        fundingRateArbitrage.deposit(10_001e6);
    }
}
