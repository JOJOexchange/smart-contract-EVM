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
    uint256 constant INITIAL_WITHDRAW_DELAY = 10; // 10 seconds

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
            INITIAL_WITHDRAW_DELAY // Add this parameter
        );

        // Set initial parameters
        reserve.setGlobalParameters(2, 3e14); // maxLeverage = 2, maxFeeRate = 3bp

        reserve.setMarketParameters(
            address(perpList[1]), // ETH market
            true,
            1e16, // 1% slippage
            10_000e6, // max exposure
            bytes32(0),
            3600
        );
    }

    /// @notice Test setting the maximum total deposit
    /// @dev This test ensures that the owner can successfully update the max total deposit
    /// and that the event is emitted correctly. It's crucial for controlling the total
    /// amount of assets the reserve can hold, which impacts the system's risk profile.
    function testSetMaxTotalDeposit() public {
        uint256 newMaxDeposit = 2_000_000e6;
        reserve.setMaxTotalDeposit(newMaxDeposit);
        assertEq(reserve.maxTotalDeposit(), newMaxDeposit);
    }

    /// @notice Test setting max total deposit by non-owner
    /// @dev This test verifies that only the contract owner can set the max total deposit.
    /// It's a critical access control check to prevent unauthorized changes to a key parameter.
    function testSetMaxTotalDepositNonOwner() public {
        vm.prank(traders[0]);
        vm.expectRevert("Ownable: caller is not the owner");
        reserve.setMaxTotalDeposit(2_000_000e6);
    }

    /// @notice Test basic deposit functionality
    /// @dev This test checks if a user can successfully deposit funds and receive the correct
    /// amount of shares. It's fundamental to ensure the core deposit mechanism works as expected.
    function testDeposit() public {
        uint256 depositAmount = 100e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        vm.stopPrank();

        assertEq(reserve.balanceOf(traders[0]), depositAmount);
    }

    /// @notice Test deposit exceeding max total deposit
    /// @dev This test ensures that deposits are rejected when they would cause the total deposit
    /// to exceed the maximum limit. It's crucial for maintaining the system's risk parameters.
    function testDepositExceedsMaxTotalDeposit() public {
        uint256 depositAmount = 1_100_000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        vm.expectRevert("Deposit exceeds max total deposit");
        reserve.deposit(depositAmount);
        vm.stopPrank();
    }

    /// @notice Test multiple deposits reaching max total deposit
    /// @dev This test verifies that the system correctly handles multiple deposits up to the
    /// maximum limit and rejects any deposit that would exceed it. It ensures the max total
    /// deposit limit is enforced across multiple transactions.
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

    /// @notice Test deposit after withdrawal
    /// @dev This test checks if a user can successfully deposit funds after making a withdrawal.
    /// It ensures that the withdrawal process doesn't interfere with subsequent deposits,
    /// maintaining the fluidity of the system.
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

    /// @notice Test deposit when contract is paused
    /// @dev This test verifies that deposits are rejected when the contract is paused.
    /// It's an important safety feature that allows the contract owner to halt deposits
    /// in case of emergencies or when maintenance is required.
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
                2000e18 // current ETH price
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
                bid: int192((dsPrice * 995) / 1000), // 0.5% slippage
                ask: int192((dsPrice * 1005) / 1000) // 0.5% slippage
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

        // Use buildOrder function to construct EOA order and signature, passing info
        (Types.Order memory eoaOrder, bytes memory eoaSignature) = buildOrder(
            eoa,
            privateKey,
            eoaPaperAmount,
            eoaCreditAmount,
            address(perpList[1])
        );

        // Use buildOrderAndContractSignature function to construct reserve order's hash and contract signature
        (, bytes memory reserveSignature) = buildOrderAndContractSignature(
            reservePaperAmount,
            reserveCreditAmount,
            address(perpList[1]),
            2000e18 // Assume current ETH price is 2000
        );

        // Construct reserve order, using the same info
        Types.Order memory reserveOrder = Types.Order({
            perp: address(perpList[1]),
            signer: address(reserve),
            paperAmount: reservePaperAmount,
            creditAmount: reserveCreditAmount,
            info: info
        });

        // Construct return data
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
            // Use the full paperAmount as the amount to fill
            // Note: we need to use abs function to get the absolute value, as paperAmount can be negative
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
        // Deposit USDC into JOJODynamicLiquidityReserve
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

        // After the trade is completed, check the total value of the reserve
        assertEq(
            reserve.getTotalValue(),
            20100210000,
            "Reserve total value should be 20100210000"
        );

        // Trader1 withdraws half of the shares
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

        // Check the amount of assets withdrawn by trader1
        assertEq(
            trader1WithdrawnAssets,
            20100210000 / 4,
            "Trader1 should withdraw 20100210000/4 assets"
        );

        // Trader0 withdraws half of the shares
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

        // Check the amount of assets withdrawn by trader0
        assertEq(
            trader0WithdrawnAssets,
            20100210000 / 4,
            "Trader0 should withdraw 20100210000/4 assets"
        );
    }

    function _getStandardInfo() internal view returns (bytes32) {
        int64 makerFeeRate = -1e14; // -1bp, considering 18 decimals
        int64 takerFeeRate = 3e14; // 3bp, considering 18 decimals
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

    /// @notice Test withdrawal delay enforcement
    /// @dev This test ensures that the withdrawal delay is properly enforced. It checks that
    /// withdrawals are rejected before the delay period and allowed after. This mechanism
    /// is crucial for preventing sudden liquidity drains and potential market manipulation.
    function testWithdrawDelay() public {
        // Deposit
        uint256 depositAmount = 1000e6;
        usdc.mint(address(this), depositAmount);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        // Request withdrawal
        uint256 sharesToWithdraw = reserve.balanceOf(address(this));
        reserve.requestWithdraw(sharesToWithdraw);

        // Attempt to execute withdrawal immediately (should fail)
        vm.expectRevert("Withdraw delay not met");
        reserve.executeWithdraw(0);

        // Wait for 9 seconds (still not enough)
        vm.warp(block.timestamp + 9);
        vm.expectRevert("Withdraw delay not met");
        reserve.executeWithdraw(0);

        // Wait for 1 more second (now should be able to withdraw)
        vm.warp(block.timestamp + 1);
        reserve.executeWithdraw(0);

        // Verify withdrawal was successful
        assertEq(reserve.balanceOf(address(this)), 0);
        assertGt(usdc.balanceOf(address(this)), 0);
    }

    /// @notice Test owner's ability to change withdrawal delay
    /// @dev This test verifies that the contract owner can successfully update the withdrawal delay.
    /// The ability to adjust this parameter is important for adapting to changing market conditions
    /// or regulatory requirements.
    function testOwnerCanChangeWithdrawDelay() public {
        uint256 newDelay = 20; // 20 seconds
        vm.prank(reserve.owner());
        reserve.setWithdrawDelay(newDelay);
        assertEq(reserve.withdrawDelay(), newDelay);
    }

    /// @notice Test setting global parameters
    /// @dev This test ensures that the owner can successfully update global parameters like
    /// max leverage and max fee rate. These parameters are crucial for controlling the overall
    /// risk profile of the system and ensuring fair fee structures.
    function testSetGlobalParameters() public {
        uint256 newMaxLeverage = 3;
        int256 newMaxFeeRate = 5e14;
        reserve.setGlobalParameters(newMaxLeverage, newMaxFeeRate);
        uint256 maxLeverage = reserve.maxLeverage();
        int256 maxFeeRate = reserve.maxFeeRate();
        assertEq(maxLeverage, newMaxLeverage);
        assertEq(maxFeeRate, newMaxFeeRate);
    }

    /// @notice Test setting global parameters by non-owner
    /// @dev This test verifies that only the contract owner can set global parameters.
    /// It's an important access control check to prevent unauthorized changes to critical system parameters.
    function testSetGlobalParametersNonOwner() public {
        vm.prank(traders[0]);
        vm.expectRevert("Ownable: caller is not the owner");
        reserve.setGlobalParameters(3, 5e14);
    }

    /// @notice Test updating external contract addresses
    /// @dev This test checks if the owner can successfully update the address of an external contract.
    /// This functionality is crucial for system upgrades or replacing faulty external dependencies.
    function testUpdateExternalContract() public {
        address newJojoDealer = address(0x123);
        reserve.updateExternalContract("jojoDealer", newJojoDealer);
        assertEq(address(reserve.jojoDealer()), newJojoDealer);
    }

    /// @notice Test updating external contract with invalid name
    /// @dev This test ensures that attempting to update an external contract with an invalid name
    /// results in an error. It prevents accidental updates to non-existent or incorrectly named contracts.
    function testUpdateExternalContractInvalidName() public {
        vm.expectRevert("Invalid contract name");
        reserve.updateExternalContract("invalidName", address(0x123));
    }

    /// @notice Test pausing and unpausing the contract
    /// @dev This test verifies the pause and unpause functionality, ensuring that deposits are
    /// blocked when paused and allowed when unpaused. This feature is critical for emergency
    /// situations or planned maintenance.
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

    /// @notice Test getting total pending withdrawals
    /// @dev This test checks if the contract correctly calculates the total pending withdrawals.
    /// Accurate tracking of pending withdrawals is crucial for managing liquidity and ensuring
    /// the system can meet all withdrawal requests.
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

    /// @notice Test transferring locked shares
    /// @dev This test ensures that users cannot transfer shares that are locked for withdrawal.
    /// It's crucial for maintaining the integrity of the withdrawal process and preventing
    /// double-spending of shares.
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

    /// @notice Test the leverage check mechanism after withdrawals in edge cases
    /// @dev This test simulates a scenario where the reserve's leverage is close to its maximum limit
    ///      and verifies that the system correctly handles withdrawals in this situation.
    ///      It's crucial for maintaining the overall risk profile of the reserve and preventing
    ///      situations where withdrawals could push the system beyond safe leverage limits.
    function testCheckLeverageAfterWithdrawEdgeCase() public {
        // Set up initial conditions
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);
        usdc.approve(address(jojoDealer), depositAmount);
        jojoDealer.deposit(depositAmount, 0, address(traders[0]));
        vm.stopPrank();
        
        // Execute a trade that brings the leverage close to the maximum allowed
        // This simulates a high-leverage situation in the reserve
        (Types.Order[] memory orders, bytes[] memory signatures) = _setupTradeWithEOAAndContractSignature(
            0, 1e18, -2100e6, -1e18, 2100e6
        );
        _executeTrade(orders, signatures);
        
        // Test Case 1: Small withdrawal should succeed
        // Even in high-leverage situations, small withdrawals should be allowed
        vm.startPrank(traders[0]);
        reserve.requestWithdraw(1e6);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        reserve.executeWithdraw(0);
        vm.stopPrank();
        
        // Test Case 2: Large withdrawal should fail
        // Attempting to withdraw a large amount should be rejected as it would push the leverage beyond the safe limit
        vm.startPrank(traders[0]);
        reserve.requestWithdraw(900e6);
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);
        vm.expectRevert("Leverage too high after withdraw");
        reserve.executeWithdraw(1);
        vm.stopPrank();
    }

    /// @notice Test executing withdrawal twice
    /// @dev This test verifies that a withdrawal request cannot be executed more than once.
    /// It prevents double-spending of withdrawal requests and ensures each request is processed only once.
    function testExecuteWithdrawTwice() public {
        // Deposit
        uint256 depositAmount = 1000e6;
        vm.startPrank(traders[0]);
        usdc.approve(address(reserve), depositAmount);
        reserve.deposit(depositAmount);

        // Request withdrawal
        uint256 sharesToWithdraw = reserve.balanceOf(traders[0]);
        reserve.requestWithdraw(sharesToWithdraw);

        // Wait for withdrawal delay
        vm.warp(block.timestamp + reserve.withdrawDelay() + 1);

        // Execute withdrawal (should succeed)
        reserve.executeWithdraw(0);

        // Attempt to execute the same withdrawal request again (should fail)
        vm.expectRevert("Withdraw already executed");
        reserve.executeWithdraw(0);

        vm.stopPrank();
    }
}
