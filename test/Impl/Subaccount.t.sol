/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.9;

import "../init/JUSDBankInit.t.sol";

contract SubaccountTest is JUSDBankInitTest {

    function getSetOperatorData(
        address op,
        bool isValid
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature("setOperator(address,bool) ", op, isValid);
    }

    function testOperatorJOJOSubaccount() public {
        eth.transfer(alice, 10e18);
        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        address aliceSub = subaccountFactory.newSubaccount();
        bytes memory data = jojoDealer.getSetOperatorCallData(alice, true);
        Subaccount(aliceSub).execute(address(jojoDealer), data, 0);
        // alice is the operator of aliceSub in JOJODealer system and can operate the sub account.
        assertEq(IDealer(jojoDealer).isOperatorValid(aliceSub, alice), true);

        // aliceSub is the operator of alice in JUSD system and can operate alice
        // so that aliceSub can control alice to deposit collateral to subaccount
        // deposit can be devided into two situation:
        // 1. main account can deposit directly into sub account.
        jusdBank.deposit(alice, address(eth), 1e18, aliceSub);
        // 2. multicall deposit and borrow, in this situation,
        // users need to let aliceSub operate main account, and borrow from subaccount
        jusdBank.setOperator(aliceSub, true);
        bytes memory dataDeposit = jusdBank.getDepositData(
            alice,
            address(eth),
            1e18,
            aliceSub
        );
        bytes memory dataBorrow = jusdBank.getBorrowData(
            500e6,
            aliceSub,
            false
        );
        bytes[] memory multiCallData = new bytes[](2);
        multiCallData[0] = dataDeposit;
        multiCallData[1] = dataBorrow;
        bytes memory excuteData = abi.encodeWithSignature(
            "multiCall(bytes[])",
            multiCallData
        );
        Subaccount(aliceSub).execute(address(jusdBank), excuteData, 0);
        console.log(
            "aliceSub deposit",
            jusdBank.getDepositBalance(address(eth), aliceSub)
        );
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));
        console.log("alice borrow", jusdBank.getBorrowBalance(alice));

        bytes memory dataWithdraw = jusdBank.getWithdrawData(
            address(eth),
            5e17,
            alice,
            false
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataWithdraw, 0);
        console.log(
            "aliceSub deposit",
            jusdBank.getDepositBalance(address(eth), aliceSub)
        );

        // flashloan situation
        // subaccount call flashloan and repay to it's own account
        bytes memory swapParam = abi.encodeWithSignature(
            "swapToUSDC(uint256,address)",
            2e17,
            address(eth)
        );
        bytes memory param = abi.encode(
            address(swapContract),
            address(swapContract),
            200e6,
            swapParam
        );
        bytes memory dataFlashloan = abi.encodeWithSignature(
            "flashLoan(address,address,uint256,address,bytes)",
            address(flashLoanRepay),
            address(eth),
            2e17,
            aliceSub,
            param
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataFlashloan, 0);
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));

        // main account call flashloan function repay to other account
        jusdBank.deposit(alice, address(eth), 1e18, alice);
        swapParam = abi.encodeWithSignature(
            "swapToUSDC(uint256,address)",
            3e17,
            address(eth)
        );
        param = abi.encode(
            address(swapContract),
            address(swapContract),
            300e6,
            swapParam
        );
        jusdBank.flashLoan(
            address(flashLoanRepay),
            address(eth),
            3e17,
            aliceSub,
            param
        );
        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));

        assertEq(jusdBank.getBorrowBalance(aliceSub), 0);

        //        bytes memory dataDepositETH = abi.encodeWithSignature("deposit()");
        //        Subaccount(aliceSub).execute{value: 2 ether}(address(mockDepositETH), dataDepositETH, 1 ether);
        //        uint256 balance = address(mockDepositETH).balance;
        //        assertEq(balance, 1 ether);

        vm.stopPrank();

        vm.startPrank(bob);
        bytes memory dataBob = jojoDealer.getSetOperatorCallData(bob, true);
        cheats.expectRevert("Ownable: caller is not the owner");
        Subaccount(aliceSub).execute(address(jusdBank), dataBob, 0);
    }

    function testJOJOSubaccountRepayFromPerp() public {
        eth.transfer(alice, 10e18);
        usdc.mint(alice, 1000e6);
        jusd.mint(1000e6);
        jusd.transfer(alice, 1000e6);
        vm.startPrank(alice);
        eth.approve(address(jusdBank), 10e18);
        address aliceSub = subaccountFactory.newSubaccount();
        bytes memory data = jojoDealer.getSetOperatorCallData(alice, true);
        Subaccount(aliceSub).execute(address(jojoDealer), data, 0);
        // alice is the operator of aliceSub in JOJODealer system and can operate the sub account.
        assertEq(IDealer(jojoDealer).isOperatorValid(aliceSub, alice), true);

        jusd.approve(address(jojoDealer), 1000e6);
        usdc.approve(address(jojoDealer), 1000e6);
        jojoDealer.deposit(1000e6, 1000e6, aliceSub);

        // aliceSub is the operator of alice in JUSD system and can operate alice
        // so that aliceSub can control alice to deposit collateral to subaccount
        // deposit can be devided into two situation:
        // 1. main account can deposit directly into sub account.
        jusdBank.deposit(alice, address(eth), 1e18, aliceSub);
        // 2. multicall deposit and borrow, in this situation,
        // users need to let aliceSub operate main account, and borrow from subaccount
        jusdBank.setOperator(aliceSub, true);
        bytes memory dataBorrow = jusdBank.getBorrowData(
            500e6,
            aliceSub,
            false
        );
        Subaccount(aliceSub).execute(address(jusdBank), dataBorrow, 0);

        // withdraw USDC or JUSD from trading account, and repay it to JUSDBank
        bytes memory repayParam = abi.encodeWithSignature(
            "repayToBank(address,address)",
            0x518638a658aCd9A3A06cd4c9f44829305a6a8df4,
            0x518638a658aCd9A3A06cd4c9f44829305a6a8df4
        );
        emit log_bytes(repayParam);
        bytes memory fastWithdraw = abi.encodeWithSignature(
            "fastWithdraw(address,address,uint256,uint256,bool,bytes)",
            aliceSub,
            jusdRepayHelper,
            500e6,
            0,
            false,
            repayParam
        );
        Subaccount(aliceSub).execute(address(jojoDealer), fastWithdraw, 0);

        console.log("aliceSub borrow", jusdBank.getBorrowBalance(aliceSub));
        console.log(
            "repay amount still",
            jusd.balanceOf(address(jusdRepayHelper))
        );
    }
}
