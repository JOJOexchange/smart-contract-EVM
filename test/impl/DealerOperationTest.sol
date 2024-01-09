/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "../init/TradingInit.sol";
import "../utils/Checkers.sol";

// Check dealer's operation
contract OperationTest is Checkers {
    function testRemovePerp() public {
        Types.RiskParams memory paramETH2 = Types.RiskParams({
            initialMarginRatio: 1e17,
            liquidationThreshold: 5e16,
            liquidationPriceOff: 1e16,
            insuranceFeeRate: 1e16,
            markPriceSource: address(priceSourceList[1]),
            name: "ETH",
            isRegistered: false
        });
        jojoDealer.setPerpRiskParams(address(perpList[1]), paramETH2);
        address[] memory perps2 = jojoDealer.getAllRegisteredPerps();
        assertEq(perps2.length, 1);
    }

    function testOnlyRegisteredPerp() public {
        cheats.expectRevert("JOJO_PERP_NOT_REGISTERED");
        jojoDealer.approveTrade(traders[0], "0x00");

        cheats.expectRevert("JOJO_PERP_NOT_REGISTERED");
        jojoDealer.requestLiquidation(traders[0], traders[1], traders[0], 0);

        cheats.expectRevert("JOJO_PERP_NOT_REGISTERED");
        jojoDealer.openPosition(traders[0]);

        cheats.expectRevert("JOJO_PERP_NOT_REGISTERED");
        jojoDealer.realizePnl(traders[0], 0);
    }

    function testInvalidRiskParam() public {
        Types.RiskParams memory paramBTC2 = Types.RiskParams({
            initialMarginRatio: 5e16,
            liquidationThreshold: 3e16,
            liquidationPriceOff: 2e16,
            insuranceFeeRate: 2e16,
            markPriceSource: address(priceSourceList[0]),
            name: "BTC",
            isRegistered: true
        });
        cheats.expectRevert("JOJO_INVALID_RISK_PARAM");
        jojoDealer.setPerpRiskParams(address(perpList[0]), paramBTC2);
    }

    function testSecondaryAssetCanNotChange() public {
        cheats.expectRevert("JOJO_SECONDARY_ASSET_ALREADY_EXIST");
        jojoDealer.setSecondaryAsset(address(perpList[0]));
        jojoDealer.disableFastWithdraw(true);
    }

    function testSetSecondary() public {
        JOJODealer jd = new JOJODealer(address(usdc));
        TestERC20 fake = new TestERC20("fake", "fake", 20);
        cheats.expectRevert("JOJO_SECONDARY_ASSET_DECIMAL_WRONG");
        jd.setSecondaryAsset(address(fake));
    }
}
