/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";
import "../mocks/MockUniswapOracle.sol";
import "../../src/oracle/UniswapPriceAdaptor.sol";

// Check jusdbank's view
contract JUSDViewTest is JUSDBankInitTest {
    function testJUSDView() public {
        TestERC20 BTC = new TestERC20("BTC", "BTC", 8);
        MockUniswapOracle MockUni = new MockUniswapOracle();
        address[] memory pools;
        UniswapPriceAdaptor UNIOracle = new UniswapPriceAdaptor(
            address(MockUni), 18, address(BTC), address(usdc), pools, 600, address(ethOracle), 100_000_000_000_000_000
        );
        UNIOracle.getAssetPrice();
        UNIOracle.getMarkPrice();
        UNIOracle.updatePools(pools);
        UNIOracle.updatePeriod(5);
        UNIOracle.updateImpact(1);
        cheats.expectRevert("deviation is too big");
        UNIOracle.getAssetPrice();

        jusdBank.initReserve(
            // token
            address(BTC),
            // maxCurrencyBorrowRate
            7e17,
            // maxDepositAmount
            2100e8,
            // maxDepositAmountPerAccount
            210e8,
            // maxBorrowValue
            100_000e18,
            // liquidateMortgageRate
            75e16,
            // liquidationPriceOff
            1e17,
            // insuranceFeeRate
            1e17,
            address(btcOracle)
        );
        BTC.mint(alice, 10e8);
        eth.transfer(alice, 100e18);

        vm.startPrank(alice);

        BTC.approve(address(jusdBank), 1e8);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        jusdBank.deposit(alice, address(BTC), 1e8, alice);

        uint256 maxMintAmount = jusdBank.getDepositMaxMintAmount(alice);
        uint256 maxWithdrawBTC = jusdBank.getMaxWithdrawAmount(address(BTC), alice);
        uint256 maxWithdrawETH = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        assertEq(maxMintAmount, 22_000_000_000);
        assertEq(maxWithdrawBTC, 1e8);
        assertEq(maxWithdrawETH, 10e18);

        jusdBank.borrow(7200e6, alice, false);
        maxWithdrawBTC = jusdBank.getMaxWithdrawAmount(address(BTC), alice);
        maxWithdrawETH = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        assertEq(maxWithdrawBTC, 100_000_000);
        assertEq(maxWithdrawETH, 10_000_000_000_000_000_000);

        jusdBank.borrow(800e6, alice, false);
        jusdBank.withdraw(address(BTC), 1e8, alice, false);
        maxWithdrawETH = jusdBank.getMaxWithdrawAmount(address(eth), alice);
        assertEq(maxWithdrawETH, 0);
        jusdBank.getTRate();
        jusdBank.accrueRate();
    }
}
