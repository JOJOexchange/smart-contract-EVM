/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/oracle/ConstOracle.sol";
import "../../src/oracle/EmergencyOracle.sol";
import "../../src/oracle/OracleAdaptor.sol";
import "../../src/oracle/OracleAdaptorWstETH.sol";
import "../mocks/MockChainLink.t.sol";
import "../mocks/MockUSDCPrice.sol";

interface Cheats {
    function expectRevert() external;

    function expectRevert(bytes calldata) external;
}

// Check oracle
contract OperationTest is Test {
    Cheats internal constant cheats = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    ConstOracle constOracle = new ConstOracle(30_000e6);
    EmergencyOracle emergency = new EmergencyOracle("BTC");
    MockChainLink mockToken1ChainLink = new MockChainLink();
    MockUSDCPrice usdcPrice = new MockUSDCPrice();
    OracleAdaptor oracleAdaptor =
        new OracleAdaptor(address(mockToken1ChainLink), 20, 86_400, 86_400, address(usdcPrice), 5e16);
    OracleAdaptor oracleAdaptor2 = new OracleAdaptor(address(mockToken1ChainLink), 20, 0, 0, address(usdcPrice), 5e16);
    OracleAdaptor oracleAdaptor3 =
        new OracleAdaptor(address(mockToken1ChainLink), 20, 86_400, 0, address(usdcPrice), 5e16);
    JOJOOracleAdaptorWstETH jojoOracleAdaptorWstETH = new JOJOOracleAdaptorWstETH(
        address(mockToken1ChainLink), 20, 86_400, address(usdcPrice), 86_400, address(mockToken1ChainLink), 86_400
    );

    JOJOOracleAdaptorWstETH jojoOracleAdaptorWstETH2 = new JOJOOracleAdaptorWstETH(
        address(mockToken1ChainLink), 20, 0, address(usdcPrice), 0, address(mockToken1ChainLink), 0
    );
    JOJOOracleAdaptorWstETH jojoOracleAdaptorWstETH3 = new JOJOOracleAdaptorWstETH(
        address(mockToken1ChainLink), 20, 86_400, address(usdcPrice), 0, address(mockToken1ChainLink), 0
    );
    JOJOOracleAdaptorWstETH jojoOracleAdaptorWstETH4 = new JOJOOracleAdaptorWstETH(
        address(mockToken1ChainLink), 20, 86_400, address(usdcPrice), 86_400, address(mockToken1ChainLink), 0
    );

    function testConstOracle() public {
        uint256 price = constOracle.getMarkPrice();
        assertEq(price, 30_000e6);
    }

    function testEmergencyOracle() public {
        emergency.turnOnOracle();
        emergency.turnOffOracle();
        cheats.expectRevert("the emergency oracle is close");
        emergency.getAssetPrice();
        cheats.expectRevert("the emergency oracle is close");
        emergency.getMarkPrice();
        assertEq(emergency.turnOn(), false);
    }

    function testOracleAdaptor() public {
        oracleAdaptor.turnOnJOJOOracle();
        oracleAdaptor.turnOffJOJOOracle();
        oracleAdaptor.updateThreshold(6e16);
        oracleAdaptor.getMarkPrice();
        oracleAdaptor.getChainLinkPrice();
        oracleAdaptor.getAssetPrice();
        oracleAdaptor.turnOnJOJOOracle();
        oracleAdaptor.setMarkPrice(1010e6);
        oracleAdaptor.getMarkPrice();
        oracleAdaptor.setMarkPrice(120e6);
        cheats.expectRevert("deviation is too big");
        oracleAdaptor.getMarkPrice();

        vm.warp(1000);
        cheats.expectRevert("ORACLE_HEARTBEAT_FAILED");
        oracleAdaptor2.getAssetPrice();
        cheats.expectRevert("USDC_ORACLE_HEARTBEAT_FAILED");
        oracleAdaptor3.getAssetPrice();
    }

    function testOracleAdaptorWstETH() public {
        jojoOracleAdaptorWstETH.getAssetPrice();
        vm.warp(1000);
        cheats.expectRevert("ORACLE_HEARTBEAT_FAILED");
        jojoOracleAdaptorWstETH2.getAssetPrice();
        cheats.expectRevert("USDC_ORACLE_HEARTBEAT_FAILED");
        jojoOracleAdaptorWstETH3.getAssetPrice();
        cheats.expectRevert("ETH_ORACLE_HEARTBEAT_FAILED");
        jojoOracleAdaptorWstETH4.getAssetPrice();
    }
}
