/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/FlashLoanRepay.sol";
import "../../src/JOJODealer.sol";
import "../../src/JUSDBank.sol";
import "../../src/JUSDExchange.sol";
import "../../src/JUSDRepayHelper.sol";
import "../../src/token/JUSD.sol";
import "../../src/oracle/EmergencyOracle.sol";
import "../../src/support/MockSwap.sol";
import "../../src/GeneralRepay.sol";
import "../../src/libraries/Types.sol";
import "../../src/subaccount/SubaccountFactory.sol";
import "../../src/support/TestERC20.sol";
import "../utils/Utils.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

contract JUSDBankInitTest is Test {
    Cheats internal constant cheats = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 public constant ONE = 1e18;

    address internal deployAddress;
    address internal alice;
    address internal bob;
    address internal insurance;
    address internal jim;

    Utils internal utils;
    JUSDBank public jusdBank;
    TestERC20 public btc;
    TestERC20 public eth;
    TestERC20 public usdc;
    JUSDExchange public jusdExchange;
    JUSDRepayHelper public jusdRepayHelper;
    JUSD public jusd;
    EmergencyOracle public btcOracle;
    EmergencyOracle public ethOracle;
    JOJODealer public jojoDealer;
    MockSwap public swapContract;
    GeneralRepay public generalRepay;
    FlashLoanRepay public flashLoanRepay;
    SubaccountFactory public subaccountFactory;
    address payable[] internal users;

    function setUpTokens() public {
        btc = new TestERC20("BTC", "BTC", 8);
        eth = new TestERC20("ETH", "ETH", 18);
        address[] memory user = new address[](1);
        user[0] = address(address(this));
        uint256[] memory amountBTC = new uint256[](1);
        amountBTC[0] = 4000e8;
        uint256[] memory amountETH = new uint256[](1);
        amountETH[0] = 40_000e18;
        btc.mintBatch(user, amountBTC);
        eth.mintBatch(user, amountETH);
        jusd = new JUSD(6);
        usdc = new TestERC20("USDC", "USDC", 6);
    }

    function initUsers() public {
        utils = new Utils();
        users = utils.createUsers(5);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        insurance = users[2];
        vm.label(insurance, "Insurance");
        jim = users[3];
        vm.label(jim, "Jim");
    }

    function initJUSDBankAndExchange() public {
        btcOracle = new EmergencyOracle("BTC oracle");
        ethOracle = new EmergencyOracle("ETH oracle");
        jusd.mint(200_000e6);
        jusd.mint(100_000e6);
        jusdBank = new JUSDBank( // maxReservesAmount_
            10,
            insurance,
            address(jusd),
            address(jojoDealer),
            // maxBorrowAmountPerAccount_
            100_000_000_000,
            // maxBorrowAmount_
            100_000_000_001,
            // borrowFeeRate_
            2e16,
            address(usdc)
        );
        deployAddress = jusdBank.owner();
        jusdBank.initReserve(
            // token
            address(btc),
            // initialMortgageRate
            7e17,
            // maxDepositAmount
            300e8,
            // maxDepositAmountPerAccount
            210e8,
            // maxBorrowValue
            100_000e6,
            // liquidateMortgageRate
            8e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(btcOracle)
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
            address(ethOracle)
        );
        ethOracle.turnOnOracle();
        btcOracle.turnOnOracle();
        ethOracle.setMarkPrice(1000e6);
        btcOracle.setMarkPrice(20_000e16);
        jusd.transfer(address(jusdBank), 200_000e6);
        jusdExchange = new JUSDExchange(address(usdc), address(jusd));
        jusd.transfer(address(jusdExchange), 100_000e6);
    }

    function initSwap() public {
        swapContract = new MockSwap(address(usdc), address(eth), address(ethOracle));
        usdc.mint(address(swapContract), 100_000e6);
    }

    function initGeneralRepay() public {
        generalRepay = new GeneralRepay(address(jusdBank), address(jusdExchange), address(usdc), address(jusd));

        flashLoanRepay = new FlashLoanRepay(address(jusdBank), address(jusdExchange), address(usdc), address(jusd));
        flashLoanRepay.setWhiteListContract(address(swapContract), true);
        generalRepay.setWhiteListContract(address(swapContract), true);
    }

    function initRepayHelper() public {
        jusdRepayHelper = new JUSDRepayHelper(address(jusdBank), address(jusd), address(usdc), address(jusdExchange));
        jusdRepayHelper.setWhiteList(address(jojoDealer), true);
    }

    function initSubaccountFactory() public {
        subaccountFactory = new SubaccountFactory();
    }

    function setUp() public {
        setUpTokens();
        jojoDealer = new JOJODealer(address(usdc));
        jojoDealer.setSecondaryAsset(address(jusd));
        initUsers();
        initJUSDBankAndExchange();
        initSwap();
        initGeneralRepay();
        initRepayHelper();
        initSubaccountFactory();
    }

    function testOwner() public {
        assertEq(deployAddress, jusdBank.owner());
    }

    function testInitMint() public {
        assertEq(jusd.balanceOf(address(jusdBank)), 200_000e6);
    }

    function testRefundJUSDBank() public {
        jusdBank.refundJUSD(100_000e6);
        assertEq(jusd.balanceOf(address(jusdBank)), 100_000e6);
    }

    function testRefundJUSDExechange() public {
        jusdExchange.refundJUSD(50_000e6);
        assertEq(jusd.balanceOf(address(jusdExchange)), 50_000e6);
    }
}
