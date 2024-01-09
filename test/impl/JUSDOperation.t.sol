/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";
import "../../src/token/JUSD.sol";

// Check jusdbank's operation
contract JUSDOperationTest is JUSDBankInitTest {
    function testJUSDMint() public {
        jusd.mint(100e6);
        assertEq(jusd.balanceOf(address(this)), 100_000_000);
    }

    function testJUSDDecimal() public {
        emit log_uint(jusd.decimals());
        assertEq(jusd.decimals(), 6);
    }

    function testInitReserveParamWrong() public {
        cheats.expectRevert("RESERVE_PARAM_ERROR");
        jusdBank.initReserve(
            // token
            address(eth),
            // maxCurrencyBorrowRate
            5e17,
            // maxDepositAmount
            180e18,
            // maxDepositAmountPerAccount
            100e18,
            // maxBorrowValue
            100_000e18,
            // liquidateMortgageRate
            9e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e17,
            address(ethOracle)
        );
    }

    function testInitReserve() public {
        jusdBank.initReserve(
            // token
            address(eth),
            // maxCurrencyBorrowRate
            5e17,
            // maxDepositAmount
            180e18,
            // maxDepositAmountPerAccount
            100e18,
            // maxBorrowValue
            100_000e18,
            // liquidateMortgageRate
            9e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e16,
            address(ethOracle)
        );
    }

    function testInitReserveTooMany() public {
        jusdBank.updateMaxReservesAmount(0);

        cheats.expectRevert("NO_MORE_RESERVE_ALLOWED");
        jusdBank.initReserve(
            // token
            address(eth),
            // maxCurrencyBorrowRate
            5e17,
            // maxDepositAmount
            180e18,
            // maxDepositAmountPerAccount
            100e18,
            // maxBorrowValue
            100_000e18,
            // liquidateMortgageRate
            9e17,
            // liquidationPriceOff
            5e16,
            // insuranceFeeRate
            1e16,
            address(ethOracle)
        );
    }

    function testUpdateMaxBorrowAmount() public {
        jusdBank.updateMaxBorrowAmount(1000e18, 10_000e18);
        assertEq(jusdBank.maxTotalBorrowAmount(), 10_000e18);
    }

    function testUpdateRiskParamWrong() public {
        cheats.expectRevert("RESERVE_PARAM_ERROR");
        jusdBank.updateRiskParam(address(eth), 9e17, 2e17, 2e17);
        cheats.expectRevert("RESERVE_PARAM_WRONG");
        jusdBank.updateRiskParam(address(eth), 5e17, 2e17, 2e17);
    }

    function testUpdateReserveParam() public {
        cheats.expectRevert("RESERVE_PARAM_WRONG");
        jusdBank.updateReserveParam(address(eth), 9e17, 100e18, 100e18, 200_000e18);
        //        assertEq(jusdBank.getInitialRate(address(eth)), 1e18);
    }

    function testSetInsurance() public {
        jusdBank.updateInsurance(address(10));
        assertEq(jusdBank.insurance(), address(10));
    }

    function testSetJOJODealer() public {
        jusdBank.updateJOJODealer(address(10));
        assertEq(jusdBank.JOJODealer(), address(10));
    }

    function testSetOracle() public {
        jusdBank.updateOracle(address(eth), address(10));
    }

    function testUpdateRate() public {
        jusdBank.updateBorrowFeeRate(1e18);
        assertEq(jusdBank.borrowFeeRate(), 1e18);
    }

    // -----------test view--------------
    function testReserveList() public {
        address[] memory list = jusdBank.getReservesList();
        assertEq(list[0], address(btc));
    }

    function testCollateralPrice() public {
        uint256 price = jusdBank.getCollateralPrice(address(eth));
        assertEq(price, 1e9);
    }

    function testCollateraltMaxMintAmount() public {
        uint256 value = jusdBank.getCollateralMaxMintAmount(address(eth), 2e18);
        assertEq(value, 1_600_000_000);
    }

    function testBurnJUSD() public {
        JUSD jusd = new JUSD(6);
        jusd.mint(1e6);
        jusd.burn(1e6);
        assertEq(jusd.totalSupply(), 0);
    }
}
