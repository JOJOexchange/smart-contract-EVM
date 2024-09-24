// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../init/TradingInit.sol";
import "../../src/smartOrders/JOJODynamicLiquidityReserve.sol";
import "../../src/oracle/ChainlinkDS.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/console.sol";

contract MockVerifierProxy is IVerifierProxy {
    function verify(
        bytes calldata _report,
        bytes calldata
    ) external payable returns (bytes memory) {
        return _report;
    }

    function verifyBulk(
        bytes[] memory _reports,
        bytes memory
    ) external payable returns (bytes[] memory) {
        return _reports;
    }

    function s_feeManager() external pure returns (IVerifierFeeManager) {
        return IVerifierFeeManager(address(0));
    }
}

contract MockUSDCFeed is IChainlink {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, 100500000, block.timestamp, block.timestamp, 0); // 1.005 USDC price with 8 decimals
    }
}

contract JOJODynamicLiquidityReserveTest is TradingInit {
    JOJODynamicLiquidityReserve public reserve;
    MockVerifierProxy public mockVerifierProxy;
    MockUSDCFeed public mockUSDCFeed;
    uint256 constant INITIAL_WITHDRAW_DELAY = 10; // 10 秒

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
            1_000_000e6, // initialMaxTotalDeposit
            INITIAL_WITHDRAW_DELAY // 添加这个参数
        );

        // 设置初始参数
        reserve.setGlobalParameters(2, 3e14); // maxLeverage = 2, maxFeeRate = 3bp

        // 设置市场参数，将滑点从 1% 增加到 10%
        reserve.setMarketParameters(
            address(perpList[1]), // ETH market
            true,
            1e16, // 1% slippage
            10_000e6, // max exposure
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
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
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

    // assume market price is 2000e18, bid is 1990e18, ask is 2010e18
    // consider USDC price 1.005, the expected price is bid 1980.099, and ask 2000
    // consider slippage 1%, the expected price is bid 1960.49, and ask 2020
    function testValidTrade(
        int128 paperAmount,
        int128 creditAmount
    ) internal returns (bool) {
        (
            bytes32 orderHash,
            bytes memory signature
        ) = buildOrderAndContractSignature(
                paperAmount,
                creditAmount,
                address(perpList[1]), // ETH market
                2000e18 // 当前ETH格
            );
        bool isValid = reserve.isValidSignature(orderHash, signature) ==
            bytes4(0x1626ba7e);
        console.log("isValid", isValid);
        return isValid;
    }

    function testSignatures() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();

        assertTrue(testValidTrade(1e18, -1960e6), "bid price should pass"); // bid price pass
        vm.expectRevert("Price check failed");
        testValidTrade(1e18, -1961e6); // bid price fail
        assertTrue(testValidTrade(-1e18, 2020e6), "ask price should pass"); // ask pass
        vm.expectRevert("Price check failed");
        testValidTrade(-1e18, 2019e6); // ask price fail

        vm.expectRevert("Leverage too high after trade");
        testValidTrade(1.1e18, -1961e6);

        depositAmount = 10000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();
        vm.expectRevert("Exceeds market exposure limit");
        testValidTrade(5.01e18, -1961e6);
    }

    function buildOrderAndContractSignature(
        int128 paperAmount,
        int128 creditAmount,
        address perpMarket,
        int192 dsPrice
    ) internal view returns (bytes32 orderHash, bytes memory) {
        bytes32 info = _getStandardInfo();
        Types.Order memory order = Types.Order({
            perp: perpMarket,
            signer: address(reserve),
            paperAmount: paperAmount,
            creditAmount: creditAmount,
            info: info
        });

        bytes memory unverifiedReport = abi.encode(
            Report({
                feedId: bytes32(0),
                validFromTimestamp: uint32(block.timestamp),
                observationsTimestamp: uint32(block.timestamp),
                nativeFee: uint192(0),
                linkFee: uint192(0),
                expiresAt: uint32(block.timestamp + 3600),
                price: dsPrice,
                bid: int192((dsPrice * 995) / 1000), // 0.5% 滑点
                ask: int192((dsPrice * 1005) / 1000) // 0.5% 滑点
            })
        );

        bytes32 domainSeparator = EIP712Test._buildDomainSeparator(
            "JOJO",
            "1",
            address(jojoDealer)
        );
        orderHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                EIP712Test._structHash(order)
            )
        );

        return (orderHash, abi.encode(order, unverifiedReport));
    }

    function _setupTradeWithEOAAndContractSignature(
        uint256 traderIndex,
        int128 eoaPaperAmount,
        int128 eoaCreditAmount,
        int128 reservePaperAmount,
        int128 reserveCreditAmount
    )
        internal
        view
        returns (Types.Order[] memory orders, bytes[] memory signatures)
    {
        address eoa = traders[traderIndex];
        uint256 privateKey = tradersKey[traderIndex];

        bytes32 info = _getStandardInfo();

        // 使用 buildOrder 函数构造 EOA 订单和签名，传入 info
        (Types.Order memory eoaOrder, bytes memory eoaSignature) = buildOrder(
            eoa,
            privateKey,
            eoaPaperAmount,
            eoaCreditAmount,
            address(perpList[1])
        );

        // 使用 buildOrderAndContractSignature 函数构造 reserve 订单的 hash 和合约签名
        (, bytes memory reserveSignature) = buildOrderAndContractSignature(
            reservePaperAmount,
            reserveCreditAmount,
            address(perpList[1]),
            2000e18 // 假设当前ETH价格为2000
        );

        // 构造 reserve 订单，使用相同的 info
        Types.Order memory reserveOrder = Types.Order({
            perp: address(perpList[1]),
            signer: address(reserve),
            paperAmount: reservePaperAmount,
            creditAmount: reserveCreditAmount,
            info: info
        });

        // 构造返回数据
        orders = new Types.Order[](2);
        signatures = new bytes[](2);
        orders[0] = eoaOrder;
        orders[1] = reserveOrder;
        signatures[0] = eoaSignature;
        signatures[1] = reserveSignature;

        return (orders, signatures);
    }

    function _executeTrade(
        Types.Order[] memory orders,
        bytes[] memory signatures
    ) internal {
        uint256[] memory matchPaperAmount = new uint256[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            // 使用订单的完整 paperAmount 作为要填充的数量
            // 注意：我们需要使用 abs 函数来获取绝对值，因为 paperAmount 可能是负数
            matchPaperAmount[i] = uint256(
                int256(
                    orders[i].paperAmount < 0
                        ? -orders[i].paperAmount
                        : orders[i].paperAmount
                )
            );
        }

        bytes memory tradeData = abi.encode(
            orders,
            signatures,
            matchPaperAmount
        );
        Perpetual(address(perpList[1])).trade(tradeData);
    }

    function testTradeWithEOAAndContractSignature() public {
        // 为 JOJODynamicLiquidityReserve 充值 USDC
        uint256 depositAmount = 10000e6;
        vm.startPrank(traders[1]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(traders[0]);
        usdc.approve(address(jojoDealer), depositAmount);
        jojoDealer.deposit(depositAmount, 0, address(traders[0]));
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();

        uint256 traderIndex = 0;
        int128 eoaPaperAmount = 1e18;
        int128 eoaCreditAmount = -2100e6;
        int128 reservePaperAmount = -1e18;
        int128 reserveCreditAmount = 2100e6;

        (
            Types.Order[] memory orders,
            bytes[] memory signatures
        ) = _setupTradeWithEOAAndContractSignature(
                traderIndex,
                eoaPaperAmount,
                eoaCreditAmount,
                reservePaperAmount,
                reserveCreditAmount
            );

        _executeTrade(orders, signatures);

        // 交易完成后，检查 reserve 的总价值
        assertEq(
            reserve.getTotalValue(),
            20100210000,
            "Reserve total value should be 20100210000"
        );

        // trader1 提取一半的 shares
        uint256 trader1Shares = reserve.balanceOf(traders[1]);
        uint256 trader1WithdrawAmount = trader1Shares / 2;
        vm.startPrank(traders[1]);
        reserve.requestWithdraw(trader1WithdrawAmount);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        uint256 balanceBefore = usdc.balanceOf(traders[1]);
        reserve.executeWithdraw(0);
        uint256 balanceAfter = usdc.balanceOf(traders[1]);
        uint256 trader1WithdrawnAssets = balanceAfter - balanceBefore;
        vm.stopPrank();

        // 检查 trader1 提取的资产数量
        assertEq(
            trader1WithdrawnAssets,
            20100210000 / 4,
            "Trader1 should withdraw 20100210000/4 assets"
        );

        // trader0 提取一半的 shares
        uint256 trader0Shares = reserve.balanceOf(traders[0]);
        uint256 trader0WithdrawAmount = trader0Shares / 2;
        vm.startPrank(traders[0]);
        reserve.requestWithdraw(trader0WithdrawAmount);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        balanceBefore = usdc.balanceOf(traders[0]);
        reserve.executeWithdraw(1);
        balanceAfter = usdc.balanceOf(traders[0]);
        uint256 trader0WithdrawnAssets = balanceAfter - balanceBefore;
        vm.stopPrank();

        // 检查 trader0 提取的资产数量
        assertEq(
            trader0WithdrawnAssets,
            20100210000 / 4,
            "Trader0 should withdraw 20100210000/4 assets"
        );
    }

    function _getStandardInfo() internal view returns (bytes32) {
        int64 makerFeeRate = -1e14; // -1bp, 考虑18位小数
        int64 takerFeeRate = 3e14; // 3bp, 考虑18位小数
        uint64 expiration = uint64(block.timestamp + 1 hours);
        uint64 nonce = 1;

        return
            bytes32(
                (uint256(uint64(makerFeeRate)) << 192) |
                    (uint256(uint64(takerFeeRate)) << 128) |
                    (uint256(expiration) << 64) |
                    uint256(nonce)
            );
    }

    function testWithdrawDelay() public {
        // 存款
        uint256 depositAmount = 1000e6;
        usdc.mint(address(this), depositAmount);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        // 请求提现
        uint256 sharesToWithdraw = reserve.balanceOf(address(this));
        reserve.requestWithdraw(sharesToWithdraw);

        // 尝试立即执行提现（应该失败）
        vm.expectRevert("Withdraw delay not met");
        reserve.executeWithdraw(0);

        // 等待9秒（仍然不够）
        vm.warp(block.timestamp + 9);
        vm.expectRevert("Withdraw delay not met");
        reserve.executeWithdraw(0);

        // 再等待1秒（现在应该可以提现）
        vm.warp(block.timestamp + 1);
        reserve.executeWithdraw(0);

        // 验证提现成功
        assertEq(reserve.balanceOf(address(this)), 0);
        assertGt(usdc.balanceOf(address(this)), 0);
    }

    function testOwnerCanChangeWithdrawDelay() public {
        uint256 newDelay = 20; // 20 秒
        vm.prank(reserve.owner());
        reserve.setWithdrawDelay(newDelay);
        assertEq(reserve.withdrawDelay(), newDelay);
    }

    function testSetGlobalParameters() public {
        uint256 newMaxLeverage = 3;
        int256 newMaxFeeRate = 5e14;
        reserve.setGlobalParameters(newMaxLeverage, newMaxFeeRate);
        uint256 maxLeverage = reserve.maxLeverage();
        int256 maxFeeRate = reserve.maxFeeRate();
        assertEq(maxLeverage, newMaxLeverage);
        assertEq(maxFeeRate, newMaxFeeRate);
    }

    function testSetGlobalParametersNonOwner() public {
        vm.prank(traders[0]);
        vm.expectRevert("Ownable: caller is not the owner");
        reserve.setGlobalParameters(3, 5e14);
    }

    function testUpdateExternalContract() public {
        address newJojoDealer = address(0x123);
        reserve.updateExternalContract("jojoDealer", newJojoDealer);
        assertEq(address(reserve.jojoDealer()), newJojoDealer);
    }

    function testUpdateExternalContractInvalidName() public {
        vm.expectRevert("Invalid contract name");
        reserve.updateExternalContract("invalidName", address(0x123));
    }

    function testPauseAndUnpause() public {
        reserve.pause();
        assertTrue(reserve.paused());
        
        vm.expectRevert("Pausable: paused");
        reserve.deposit(100e6);
        
        reserve.unpause();
        assertFalse(reserve.paused());
        
        uint256 depositAmount = 100e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();
        assertEq(reserve.balanceOf(traders[0]), depositAmount);
    }

    function testGetTotalPendingWithdrawals() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        reserve.requestWithdraw(depositAmount / 2);
        vm.stopPrank();
        
        vm.startPrank(traders[1]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        reserve.requestWithdraw(depositAmount / 4);
        vm.stopPrank();
        
        assertEq(reserve.getTotalPendingWithdrawals(), (depositAmount * 3) / 4);
    }

    function testTransferLockedShares() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        reserve.requestWithdraw(depositAmount / 2);
        
        vm.expectRevert("Transfer amount exceeds unlocked balance");
        reserve.transfer(traders[1], depositAmount);
        
        reserve.transfer(traders[1], depositAmount / 2);
        assertEq(reserve.balanceOf(traders[1]), depositAmount / 2);
        vm.stopPrank();
    }

    function testCheckLeverageAfterWithdrawEdgeCase() public {
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        usdc.approve(address(jojoDealer), depositAmount);
        jojoDealer.deposit(depositAmount, 0, address(traders[0]));
        vm.stopPrank();
        
        // 执行一笔交易，使得杠杆接近最大值
        (Types.Order[] memory orders, bytes[] memory signatures) = _setupTradeWithEOAAndContractSignature(
            0, 1e18, -2100e6, -1e18, 2100e6
        );
        _executeTrade(orders, signatures);
        
        // 尝试提取一小部分资金，应该成功
        vm.startPrank(traders[0]);
        reserve.requestWithdraw(1e6);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        reserve.executeWithdraw(0);
        vm.stopPrank();
        
        // 尝试提取大部分资金，应该失败
        vm.startPrank(traders[0]);
        reserve.requestWithdraw(900e6);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        vm.expectRevert("Leverage too high after withdraw");
        reserve.executeWithdraw(1);
        vm.stopPrank();
    }

    function testExecuteWithdrawTwice() public {
        // 存款
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        // 请求提现
        uint256 sharesToWithdraw = reserve.balanceOf(traders[0]);
        reserve.requestWithdraw(sharesToWithdraw);

        // 等待提现延迟时间
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);

        // 第一次执行提现（应该成功）
        reserve.executeWithdraw(0);

        // 尝试第二次执行相同的提现请求（应该失败）
        vm.expectRevert("Withdraw already executed");
        reserve.executeWithdraw(0);

        vm.stopPrank();
    }

}
