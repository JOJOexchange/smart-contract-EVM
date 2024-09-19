// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../init/TradingInit.sol";
import "../../src/smartOrders/JOJODynamicLiquidityReserve.sol";
import "../../src/oracle/ChainlinkDS.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockVerifierProxy is IVerifierProxy {
    function verify(bytes calldata _report, bytes calldata) external payable returns (bytes memory) {
        return _report;
    }

    function verifyBulk(bytes[] memory _reports, bytes memory) external payable returns (bytes[] memory) {
        return _reports;
    }

    function s_feeManager() external pure returns (IVerifierFeeManager) {
        return IVerifierFeeManager(address(0));
    }
}

contract MockUSDCFeed is IChainlink {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 1005000, block.timestamp, block.timestamp, 0); // 1.005 USDC price with 6 decimals
    }
}

contract JOJODynamicLiquidityReserveTest is TradingInit {
    JOJODynamicLiquidityReserve public reserve;
    MockVerifierProxy public mockVerifierProxy;
    MockUSDCFeed public mockUSDCFeed;

    function setUp() public override {
        super.setUp();
        
        mockVerifierProxy = new MockVerifierProxy();
        mockUSDCFeed = new MockUSDCFeed();
        
        reserve = new JOJODynamicLiquidityReserve(
            "JOJO Reserve",
            "JOJOR",
            address(jojoDealer),
            address(usdc),
            address(mockVerifierProxy),
            address(mockUSDCFeed),
            3600, // usdcHeartbeat
            address(usdc), // feeTokenAddress
            address(this), // feeManager
            1_000_000e6 // initialMaxTotalDeposit
        );

        // 设置初始参数
        reserve.setGlobalParameters(2, 100); // maxLeverage = 2, maxFeeRate = 100
        
        // 设置市场参数
        reserve.setMarketParameters(
            address(perpList[1]), // ETH market
            true,
            1e16, // 1% slippage
            1_000_000e6, // max exposure
            bytes32(0),
            3600
        );
    }

    function testSetMaxTotalDeposit() public {
        uint256 newMaxDeposit = 2_000_000e6;
        reserve.setMaxTotalDeposit(newMaxDeposit);
        assertEq(reserve.maxTotalDeposit(), newMaxDeposit);
    }

    function testSetMaxTotalDepositNonOwner() public {
        vm.prank(traders[0]);
        vm.expectRevert("Ownable: caller is not the owner");
        reserve.setMaxTotalDeposit(2_000_000e6);
    }

    function testDeposit() public {
        uint256 depositAmount = 100e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();

        assertEq(reserve.balanceOf(traders[0]), depositAmount);
    }

    function testDepositExceedsMaxTotalDeposit() public {
        uint256 depositAmount = 1_100_000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        vm.expectRevert("Deposit exceeds max total deposit");
        reserve.deposit(depositAmount);
        vm.stopPrank();
    }

    function testMultipleDepositsReachingMaxTotalDeposit() public {
        uint256 depositAmount = 500_000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount * 2);
        reserve.deposit(depositAmount);
        reserve.deposit(depositAmount);
        vm.expectRevert("Deposit exceeds max total deposit");
        reserve.deposit(1e6);
        vm.stopPrank();
    }

    function testDepositAfterWithdraw() public {
        uint256 depositAmount = 100e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount * 2);
        reserve.deposit(depositAmount);
        reserve.requestWithdraw(depositAmount);
        vm.warp(block.timestamp + reserve.WITHDRAW_DELAY() + 1);
        reserve.executeWithdraw(0);
        reserve.deposit(depositAmount);
        assertEq(reserve.balanceOf(traders[0]), depositAmount);
        vm.stopPrank();
    }

    function testDepositWhenPaused() public {
        reserve.pause();
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), 100e6);
        vm.expectRevert("Pausable: paused");
        reserve.deposit(100e6);
        vm.stopPrank();
    }

    function checkIsValidSignature(Types.Order memory order, bytes memory signature) internal {
        bytes32 orderHash = keccak256(abi.encode(order));
        vm.prank(address(jojoDealer));
        bool isValid = reserve.isValidSignature(orderHash, abi.encode(order, signature)) == bytes4(0x1626ba7e);
        assertTrue(isValid, "Trade should pass signature check");
    }

    function testValidTrade(int128 paperAmount, int128 creditAmount) internal {
        (Types.Order memory order, bytes memory signature) = buildOrderAndSignature(
            paperAmount,
            creditAmount,
            address(perpList[1]), // ETH market
            2000e8 // 当前ETH价格
        );

        checkIsValidSignature(order, signature);
    }

    function testInvalidTrade(int128 paperAmount, int128 creditAmount) internal {
        (Types.Order memory order, bytes memory signature) = buildOrderAndSignature(
            paperAmount,
            creditAmount,
            address(perpList[1]), // ETH market
            2000e8 // 当前ETH价格
        );

        vm.expectRevert();
        checkIsValidSignature(order, signature);
    }

    function testUnsupportedMarket() internal {
        (Types.Order memory order, bytes memory signature) = buildOrderAndSignature(
            1e8,
            -2000e6,
            address(perpList[0]), // BTC market (假设未支持)
            20000e8 // 当前BTC价格
        );

        vm.expectRevert();
        checkIsValidSignature(order, signature);
    }

    function testExceedMaxExposure() internal {
        // 首先设置一个较小的最大暴露
        reserve.setMarketParameters(
            address(perpList[1]),
            true,
            1e16,
            100e6, // 较小的最大暴露
            bytes32(0),
            3600
        );

        (Types.Order memory order, bytes memory signature) = buildOrderAndSignature(
            1e8, // 超过最大暴露的交易量
            -2000e6,
            address(perpList[1]),
            2000e8
        );

        vm.expectRevert();
        checkIsValidSignature(order, signature);
    }

    function buildOrderAndSignature(
        int128 paperAmount,
        int128 creditAmount,
        address perpMarket,
        int192 currentPrice
    ) internal view returns (Types.Order memory, bytes memory) {
        Types.Order memory order = Types.Order({
            perp: perpMarket,
            signer: address(reserve),
            paperAmount: paperAmount,
            creditAmount: creditAmount,
            info: bytes32(0) // 这里需要根据实际情况设置正确的 info 值
        });

        bytes memory unverifiedReport = abi.encode(
            Report({
                feedId: bytes32(0),
                validFromTimestamp: uint32(block.timestamp),
                observationsTimestamp: uint32(block.timestamp),
                nativeFee: uint192(0),
                linkFee: uint192(0),
                expiresAt: uint32(block.timestamp + 3600),
                price: currentPrice,
                bid: int192(currentPrice * 995 / 1000), // 0.5% 滑点
                ask: int192(currentPrice * 1005 / 1000) // 0.5% 滑点
            })
        );

        return (order, abi.encode(order, unverifiedReport));
    }
}