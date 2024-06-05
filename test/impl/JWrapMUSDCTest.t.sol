/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.19;

import "../init/JUSDBankInit.t.sol";
import "../mocks/MockController.sol";
import "../mocks/MockMUSDC.sol";
import "../../src/token/JWrapMUSDC.sol";

contract JWrapMUSDCTest is JUSDBankInitTest {
    MockMUSDC public mUsdc;
    TestERC20 public well;
    JWrapMUSDC public jWrapMUSDC;
    MockController public mockController;

    function setUpMtokenInfo() public {
        mUsdc = new MockMUSDC("mUsdc", "mUsdc", 8, address(usdc));
        usdc.mint(address(mUsdc), 10_000e6);
        well = new TestERC20("well", "well", 18);
        mockController = new MockController(address(well), address(usdc));
        well.mint(address(mockController), 10e18);
        usdc.mint(address(mockController), 10e6);
        jWrapMUSDC = new JWrapMUSDC(address(mUsdc), address(usdc), address(mockController), address(well), address(jusdBank));
    }

    function testDepositJwrapToken() public {
        setUpMtokenInfo();
        vm.startPrank(alice);
        jWrapMUSDC.decimals();
        mUsdc.mint(alice, 50_000e8);

        mUsdc.approve(address(jWrapMUSDC), 50_000e8);
        jWrapMUSDC.deposit(50_000e8);
        assertEq(jWrapMUSDC.getIndex(), 1e18);

        jWrapMUSDC.withdraw(50000e8);
        assertEq(jWrapMUSDC.getIndex(), 1e18);
    }

    function testClaimReward() public {
        setUpMtokenInfo();
        EmergencyOracle wellOracle = new EmergencyOracle("Well oracle");
        wellOracle.setMarkPrice(1e6);
        swapContract.addTokenPrice(address(well), address(wellOracle));
        vm.startPrank(alice);
        mUsdc.mint(alice, 50_000e8);
        mUsdc.approve(address(jWrapMUSDC), 50_000e8);
        jWrapMUSDC.deposit(50_000e8);
        vm.stopPrank();

        jWrapMUSDC.claimReward();
        bytes memory data = swapContract.getSwapToUSDCData(1e18, address(well));
        bytes memory param = jWrapMUSDC.buildSpotSwapData(address(swapContract), address(swapContract), data);
        jWrapMUSDC.swapWellToUSDC(1e18, 1e6, param);
        jWrapMUSDC.swapUSDCToMUSDC();
        assertEq(jWrapMUSDC.getIndex(), 1002e15);
        assertEq(jWrapMUSDC.rewardAdd(), 100e8);

        vm.startPrank(bob);
        mUsdc.mint(bob, 50_000e8);
        mUsdc.approve(address(jWrapMUSDC), 50_000e8);
        jWrapMUSDC.deposit(50_000e8);
        assertEq(jWrapMUSDC.getIndex(), 1002000000000084284);
        assertEq(jWrapMUSDC.balanceOf(bob), 4990019960079);
        vm.stopPrank();

        jWrapMUSDC.claimReward();
        jWrapMUSDC.swapWellToUSDC(1e18, 1e6, param);
        jWrapMUSDC.swapUSDCToMUSDC();
        assertEq(jWrapMUSDC.rewardAdd(), 200e8);

        vm.startPrank(alice);
        jWrapMUSDC.approve(address(jWrapMUSDC), 50000e8);
        jWrapMUSDC.withdraw(50000e8);
        
        assertEq(mUsdc.balanceOf(alice), 5015004995005);
        vm.stopPrank();

        jWrapMUSDC.refundMUSDC();
        assertEq(mUsdc.balanceOf(address(this)), 0);

        jWrapMUSDC.claimRewardAndSwap(1e18, 1e6, param);
        assertEq(jWrapMUSDC.rewardAdd(), 300e8);
        

    }
}
