// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/token/veJOJO.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name, 
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        // Mint initial supply to msg.sender (test contract)
        _mint(msg.sender, 1000000 * 10 ** decimals_);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract VeJOJOTest is Test {
    veJOJO public veJOJOContract;
    MockToken public jojoToken;
    MockToken public usdcToken;
    
    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant MAX_LOCK = 4 * YEAR;

    function setUp() public {
        vm.startPrank(owner);
        // JOJO token has 18 decimals
        jojoToken = new MockToken("JOJO", "JOJO", 18);
        // USDC token has 6 decimals
        usdcToken = new MockToken("USDC", "USDC", 6);
        veJOJOContract = new veJOJO(address(jojoToken), address(usdcToken));

        // Transfer tokens to test users
        // For JOJO: 1000 * 10^18 = 1000e18
        jojoToken.transfer(alice, 1000e18);
        jojoToken.transfer(bob, 1000e18);
        // For USDC: 10000 * 10^6 = 10000e6
        usdcToken.transfer(owner, 10000e6);

        vm.stopPrank();

    }

    /*********************************
     *    Basic Functionality Tests   *
     *********************************/

    function testBasicDeposit() public {
        // Test basic deposit functionality
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        
        // Alice deposits 100 JOJO for 1 year
        veJOJOContract.deposit(100e18, YEAR);
        
        // Check lock info
        (uint256 amount, uint256 end, uint256 veJOJOAmount, uint256 rewardDebt, address delegate) = veJOJOContract.userLocks(alice, 0);
        assertEq(amount, 100e18, "Incorrect locked amount");
        assertEq(end, block.timestamp + YEAR, "Incorrect lock end time");
        assertEq(veJOJOAmount, 25e18, "Incorrect veJOJO amount");
        assertEq(delegate, alice, "Incorrect initial delegate");
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        // Test multiple deposits from same user
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 200e18);
        
        veJOJOContract.deposit(100e18, YEAR);
        veJOJOContract.deposit(100e18, 2 * YEAR);
        
        assertEq(veJOJOContract.userLockCount(alice), 2, "Incorrect lock count");
        assertEq(veJOJOContract.balanceOf(alice), 75e18, "Incorrect total veJOJO balance"); // 25e18 + 50e18
        vm.stopPrank();
    }

    /*********************************
     *       Reward Tests            *
     *********************************/

    function testRewardDistribution() public {
        // Setup initial deposits
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR); // 25e18 veJOJO
        vm.stopPrank();

        vm.startPrank(bob);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, 2 * YEAR); // 50e18 veJOJO
        vm.stopPrank();

        // Owner adds rewards (USDC has 6 decimals)
        vm.startPrank(owner);
        usdcToken.approve(address(veJOJOContract), 1000e6);
        veJOJOContract.addReward(1000e6);
        vm.stopPrank();
        // 原有的断言
        assertEq(veJOJOContract.pendingReward(alice), 333333325, "Incorrect Alice reward");
        assertEq(veJOJOContract.pendingReward(bob), 666666650, "Incorrect Bob reward");
    }

    function testRewardClaim() public {
        // Setup deposits and rewards
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR);
        vm.stopPrank();

        vm.startPrank(owner);
        usdcToken.approve(address(veJOJOContract), 1000e6);
        veJOJOContract.addReward(1000e6);
        vm.stopPrank();

        // Claim rewards
        uint256 aliceBalanceBefore = usdcToken.balanceOf(alice);
        vm.prank(alice);
        veJOJOContract.claimReward();
        uint256 aliceBalanceAfter = usdcToken.balanceOf(alice);

        assertTrue(aliceBalanceAfter > aliceBalanceBefore, "No rewards received");
    }

    /*********************************
     *       Security Tests          *
     *********************************/

    function testCannotWithdrawBeforeLockEnd() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR);
        
        vm.expectRevert("Lock period not ended");
        veJOJOContract.withdraw(0);
        vm.stopPrank();
    }

    function testCannotWithdrawOthersLock() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("Invalid lock ID");
        veJOJOContract.withdraw(0);
        vm.stopPrank();
    }

    function testWithdrawAfterLockEnd() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR);
        
        // Fast forward past lock period
        vm.warp(block.timestamp + YEAR + 1);
        
        uint256 balanceBefore = jojoToken.balanceOf(alice);
        veJOJOContract.withdraw(0);
        uint256 balanceAfter = jojoToken.balanceOf(alice);
        
        assertEq(balanceAfter - balanceBefore, 100e18, "Incorrect withdrawal amount");
        vm.stopPrank();
    }

    /*********************************
     *     Edge Cases Tests          *
     *********************************/

    function testMinimumLockPeriod() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        
        vm.expectRevert("Lock time must be between 1 week and 4 years");
        veJOJOContract.deposit(100e18, WEEK - 1);
        vm.stopPrank();
    }

    function testMaximumLockPeriod() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        
        vm.expectRevert("Lock time must be between 1 week and 4 years");
        veJOJOContract.deposit(100e18, MAX_LOCK + 1);
        vm.stopPrank();
    }

    function testZeroDeposit() public {
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        
        vm.expectRevert("Amount must be greater than 0");
        veJOJOContract.deposit(0, YEAR);
        vm.stopPrank();
    }

    function testRewardCalculationAccuracy() public {
        // Test reward calculation with multiple deposits and claims
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 200e18);
        veJOJOContract.deposit(100e18, YEAR);
        vm.stopPrank();

        vm.startPrank(owner);
        usdcToken.approve(address(veJOJOContract), 2000e6);
        veJOJOContract.addReward(1000e6);
        vm.stopPrank();

        vm.startPrank(bob);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, 2 * YEAR);
        vm.stopPrank();

        vm.startPrank(owner);
        veJOJOContract.addReward(1000e6);
        vm.stopPrank();

        // Verify that total claimed rewards match the total rewards added
        uint256 alicePending = veJOJOContract.pendingReward(alice);
        uint256 bobPending = veJOJOContract.pendingReward(bob);
        assertApproxEqRel(alicePending + bobPending, 2000e6, 1e16, "Total rewards mismatch");
    }

    function testLateDeposit() public {
        // 1. Initial setup: Alice deposits
        vm.startPrank(alice);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, YEAR); // 25e18 veJOJO
        vm.stopPrank();

        // 2. First reward distribution
        vm.startPrank(owner);
        usdcToken.approve(address(veJOJOContract), 2000e6);
        veJOJOContract.addReward(1000e6); // First 1000 USDC reward
        vm.stopPrank();

        // Print first reward state
        console.log("=== After First Reward ===");
        console.log("Alice veJOJO balance:", veJOJOContract.balanceOf(alice));
        console.log("Alice pending reward:", veJOJOContract.pendingReward(alice));
        console.log("accRewardPerShare:", veJOJOContract.accRewardPerShare());

        // 3. Bob comes late and deposits
        vm.startPrank(bob);
        jojoToken.approve(address(veJOJOContract), 100e18);
        veJOJOContract.deposit(100e18, 2 * YEAR); // 50e18 veJOJO
        vm.stopPrank();

        // Print state after Bob's deposit
        console.log("=== After Bob's Deposit ===");
        console.log("Total veJOJO supply:", veJOJOContract.totalSupply());
        console.log("Bob veJOJO balance:", veJOJOContract.balanceOf(bob));
        console.log("Bob pending reward:", veJOJOContract.pendingReward(bob));
        
        // Verify Bob has no pending rewards yet
        assertEq(veJOJOContract.pendingReward(bob), 0, "Bob should not have any rewards yet");

        // 4. Second reward distribution
        vm.startPrank(owner);
        veJOJOContract.addReward(1000e6); // Second 1000 USDC reward
        vm.stopPrank();

        // Print final state
        console.log("=== After Second Reward ===");
        uint256 alicePending = veJOJOContract.pendingReward(alice);
        uint256 bobPending = veJOJOContract.pendingReward(bob);
        console.log("Alice final pending reward:", alicePending);
        console.log("Bob final pending reward:", bobPending);
        console.log("Total pending rewards:", alicePending + bobPending);

        // 5. Verify the rewards distribution
        // For first 1000 USDC: Alice gets all (1000e6)
        // For second 1000 USDC: Alice gets 1/3 (333.333333e6), Bob gets 2/3 (666.666666e6)
        // So Alice total should be around 1333.333333e6
        // And Bob total should be around 666.666666e6
        assertApproxEqRel(
            alicePending,
            1333333333, // 1000e6 + (1000e6 / 3)
            1e16,
            "Incorrect Alice total reward"
        );
        assertApproxEqRel(
            bobPending,
            666666666, // (1000e6 * 2 / 3)
            1e16,
            "Incorrect Bob reward"
        );

        // 6. Verify total rewards are correct
        assertApproxEqRel(
            alicePending + bobPending,
            2000e6, // Total rewards distributed
            1e16,
            "Total rewards mismatch"
        );

        // 7. Both users claim their rewards
        uint256 aliceUsdcBefore = usdcToken.balanceOf(alice);
        uint256 bobUsdcBefore = usdcToken.balanceOf(bob);

        vm.prank(alice);
        veJOJOContract.claimReward();
        vm.prank(bob);
        veJOJOContract.claimReward();

        uint256 aliceUsdcAfter = usdcToken.balanceOf(alice);
        uint256 bobUsdcAfter = usdcToken.balanceOf(bob);

        console.log("=== After Claims ===");
        console.log("Alice actual USDC received:", aliceUsdcAfter - aliceUsdcBefore);
        console.log("Bob actual USDC received:", bobUsdcAfter - bobUsdcBefore);

        // 8. Verify rewards are claimed correctly
        assertEq(aliceUsdcAfter - aliceUsdcBefore, alicePending, "Alice didn't receive correct USDC amount");
        assertEq(bobUsdcAfter - bobUsdcBefore, bobPending, "Bob didn't receive correct USDC amount");
    }

    // 新增：测试委托功能
    function testDelegate() public {
        // 准备测试账户
        address delegatee = address(0x123);
        vm.label(delegatee, "Delegatee");

        // 用户存入 JOJO
        uint256 depositAmount = 1000e18;
        uint256 lockTime = 365 days;
        vm.startPrank(owner);
        jojoToken.transfer(address(this), depositAmount);
        vm.stopPrank();
        
        jojoToken.approve(address(veJOJOContract), depositAmount);
        veJOJOContract.deposit(depositAmount, lockTime);

        uint256 lockId = 0;
        uint256 expectedVeJOJOAmount = veJOJOContract.calculateVeJOJO(depositAmount, lockTime);

        // 验证初始状态
        assertEq(veJOJOContract.getVotes(address(this)), expectedVeJOJOAmount, "Initial votes should be assigned to self");
        assertEq(veJOJOContract.getVotes(delegatee), 0, "Delegatee should have no votes initially");

        // 委托投票权
        veJOJOContract.delegate(lockId, delegatee);

        // 验证委托后的状态
        assertEq(veJOJOContract.getVotes(address(this)), 0, "Delegator should have no votes after delegation");
        assertEq(veJOJOContract.getVotes(delegatee), expectedVeJOJOAmount, "Delegatee should have received votes");

        // 验证重复委托到同一地址会失败
        vm.expectRevert("Already delegated to this address");
        veJOJOContract.delegate(lockId, delegatee);

        // 更改委托对象
        address newDelegatee = address(0x456);
        vm.label(newDelegatee, "New Delegatee");
        veJOJOContract.delegate(lockId, newDelegatee);

        // 验证更改委托后的状态
        assertEq(veJOJOContract.getVotes(delegatee), 0, "Old delegatee should have no votes");
        assertEq(veJOJOContract.getVotes(newDelegatee), expectedVeJOJOAmount, "New delegatee should have received votes");
    }

    function testDelegateWithdraw() public {
        // 准备测试账户
        address delegatee = address(0x123);
        vm.label(delegatee, "Delegatee");

        // 用户存入 JOJO
        uint256 depositAmount = 1000e18;
        uint256 lockTime = 7 days;
        vm.startPrank(owner);
        jojoToken.transfer(address(this), depositAmount);
        vm.stopPrank();
        
        jojoToken.approve(address(veJOJOContract), depositAmount);
        veJOJOContract.deposit(depositAmount, lockTime);

        uint256 lockId = 0;
        uint256 expectedVeJOJOAmount = veJOJOContract.calculateVeJOJO(depositAmount, lockTime);

        // 委托投票权
        veJOJOContract.delegate(lockId, delegatee);
        assertEq(veJOJOContract.getVotes(delegatee), expectedVeJOJOAmount, "Delegatee should have received votes");

        // 时间快进到锁定期结束
        vm.warp(block.timestamp + lockTime);

        // 提取锁定的 JOJO
        veJOJOContract.withdraw(lockId);

        // 验证提取后的状态
        assertEq(veJOJOContract.getVotes(delegatee), 0, "Delegatee should have no votes after withdrawal");
        assertEq(jojoToken.balanceOf(address(this)), depositAmount, "Should have received back all JOJO tokens");
    }

    function testDelegateInvalidCases() public {
        uint256 depositAmount = 1000e18;
        uint256 lockTime = 7 days;
        vm.startPrank(owner);
        jojoToken.transfer(address(this), depositAmount);
        vm.stopPrank();
        
        jojoToken.approve(address(veJOJOContract), depositAmount);
        veJOJOContract.deposit(depositAmount, lockTime);

        uint256 lockId = 0;

        // 测试委托给零地址
        vm.expectRevert("Cannot delegate to zero address");
        veJOJOContract.delegate(lockId, address(0));

        // 测试无效�� lockId
        vm.expectRevert("Invalid lock ID");
        veJOJOContract.delegate(99, address(0x123));

        // 时间快进到锁定期结束
        vm.warp(block.timestamp + lockTime);

        // 测试已过期的锁定期
        vm.expectRevert("Lock expired");
        veJOJOContract.delegate(lockId, address(0x123));

        // 提取后尝试委托
        veJOJOContract.withdraw(lockId);
        vm.expectRevert("No locked JOJO");
        veJOJOContract.delegate(lockId, address(0x123));
    }

    function testSelfDelegateVotes() public {
        // 用户存入 JOJO，此时投票权应该在自己名下
        uint256 depositAmount = 1000e18;
        uint256 lockTime = 365 days;
        vm.startPrank(owner);
        jojoToken.transfer(address(this), depositAmount);
        vm.stopPrank();
        
        jojoToken.approve(address(veJOJOContract), depositAmount);
        veJOJOContract.deposit(depositAmount, lockTime);

        uint256 expectedVeJOJOAmount = veJOJOContract.calculateVeJOJO(depositAmount, lockTime);

        // 验证投票权在自己名下
        assertEq(veJOJOContract.getVotes(address(this)), expectedVeJOJOAmount, "Initial votes should be self-delegated");

        // 再次存入，验证投票权累加
        vm.startPrank(owner);
        jojoToken.transfer(address(this), depositAmount);
        vm.stopPrank();
        
        jojoToken.approve(address(veJOJOContract), depositAmount);
        veJOJOContract.deposit(depositAmount, lockTime);

        // 验证投票权正确累加
        assertEq(veJOJOContract.getVotes(address(this)), expectedVeJOJOAmount * 2, "Votes should accumulate correctly");

        // 等待锁定期结束
        vm.warp(block.timestamp + lockTime);

        // 提取第一笔存款
        veJOJOContract.withdraw(0);

        // 验证投票权正确减少
        assertEq(veJOJOContract.getVotes(address(this)), expectedVeJOJOAmount, "Votes should decrease after withdrawal");

        // 提取第二笔存款
        veJOJOContract.withdraw(1);

        // 验证投票权完全清零
        assertEq(veJOJOContract.getVotes(address(this)), 0, "Votes should be zero after all withdrawals");
    }
}
