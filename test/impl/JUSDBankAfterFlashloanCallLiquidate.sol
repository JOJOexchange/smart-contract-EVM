/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/JUSDBankInit.t.sol";

struct LiquidateData {
    uint256 actualCollateral;
    uint256 insuranceFee;
    uint256 actualLiquidatedT0;
    uint256 actualLiquidated;
    uint256 liquidatedRemainUSDC;
}

// Check jusdbank's liquidation and flash loan
contract JUSDExploitTest is JUSDBankInitTest {
    // add this to be excluded from coverage report
    function test() public { }

    // Alice deposit 10e18 JUSD
    // Bob deposit 10e18 JUSD
    // Alice borrow 10e18 JUSD
    function testAfterFlashloanLiquidate() public {
        Repay flashloanRepay = new Repay(address(eth), address(jusdBank), address(jusdExchange), insurance);
        Attack attack =
            new Attack(address(eth), address(jusdBank), address(jusdExchange), insurance, address(flashloanRepay));

        eth.transfer(alice, 10e18);
        eth.transfer(address(flashloanRepay), 10e18);
        // change msg.sender
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        jusdBank.deposit(alice, address(eth), 10e18, alice);
        uint256 maxBorrow = jusdBank.getDepositMaxMintAmount(alice);
        jusdBank.borrow((maxBorrow * 90) / 100, alice, false);
        uint256 jusdBalance = jusd.balanceOf(alice);
        console.log("Alice jusd balance : %d", jusdBalance); //8e8

        bytes memory param = abi.encode(
            address(jusdBank), address(jusdExchange), address(eth), address(jusd), insurance, address(flashloanRepay)
        );

        cheats.expectRevert("ReentrancyGuard: Withdraw or Borrow or Liquidate flashLoan reentrant call");
        jusdBank.flashLoan(address(attack), address(eth), 10e18 - 1, alice, param);
        vm.stopPrank();
        // hack end
        console.log("HackEnd");
        uint256 flashloanRepayJusdBalance = jusd.balanceOf(address(flashloanRepay));
        uint256 flashloanRepayethBalance = eth.balanceOf(address(flashloanRepay));
        console.log("Alice jusd balance : %d", jusd.balanceOf(alice)); //0
        console.log("Alice eth balance : %d", eth.balanceOf(alice)); //0
        console.log("flashloanRepay jusd balance : %d", flashloanRepayJusdBalance); //8e8
        console.log("flashloanRepay eth balance : %d", flashloanRepayethBalance); //0
    }
}

contract Attack {
    // add this to be excluded from coverage report
    function test() public { }

    address public eth;
    address public jusdBank;
    address public jusdExchange;
    address public jusd;
    address public insurance;
    address public flashloanRepay;

    constructor(address _eth, address _jusdBank, address _jusdExchange, address _insurance, address _flashloanRepay) {
        eth = _eth;
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        insurance = _insurance;
        flashloanRepay = _flashloanRepay;
    }

    function JOJOFlashLoan(
        address asset, //eth
        uint256,
        address to, //alice
        bytes calldata param
    )
        external
    {
        bytes memory afterParam = abi.encode(flashloanRepay, param);

        JUSDBank(jusdBank).liquidate(to, address(eth), address(this), 1, afterParam, 0);
        IERC20(asset).transfer(to, IERC20(asset).balanceOf(address(this)));
    }
}

contract Repay {
    // add this to be excluded from coverage report
    function test() public { }

    address public eth;
    address public jusdBank;
    address public jusdExchange;
    address public insurance;

    constructor(address _eth, address _jusdBank, address _jusdExchange, address _insurance) {
        eth = _eth;
        jusdBank = _jusdBank;
        jusdExchange = _jusdExchange;
        insurance = _insurance;
    }

    function JOJOFlashLoan(
        address asset, //eth
        uint256,
        address to, //alice
        bytes calldata param
    )
        external
    {
        (LiquidateData memory liquidateData,) = abi.decode(param, (LiquidateData, bytes));
        uint256 assetAmount = IERC20(asset).balanceOf(address(this));
        IERC20(asset).approve(jusdBank, 10e18);
        // 2. insurance
        IERC20(asset).transfer(insurance, liquidateData.insuranceFee);
        // 3. liquidate usdc
        if (liquidateData.liquidatedRemainUSDC != 0) {
            IERC20(asset).transfer(to, liquidateData.liquidatedRemainUSDC);
        }
        // 4. transfer to liquidator
        IERC20(asset).transfer(
            to,
            assetAmount - liquidateData.insuranceFee - liquidateData.actualLiquidated
                - liquidateData.liquidatedRemainUSDC
        );
    }
}
