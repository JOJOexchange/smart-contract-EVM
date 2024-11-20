// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract veJOJO is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable JOJO;
    IERC20 public immutable USDC;
    
    struct LockInfo {
        uint256 amount;
        uint256 end;
        uint256 veJOJOAmount;
        uint256 rewardDebt;
    }

    mapping(address => mapping(uint256 => LockInfo)) public userLocks;
    mapping(address => uint256) public userLockCount;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;
    uint256 public constant REWARD_PERIOD = 7 days;

    uint256 private constant MAX_LOCK_TIME = 4 * 365 days;

    event Deposit(address indexed user, uint256 lockId, uint256 amount, uint256 lockTime, uint256 veJOJOAmount);
    event Withdraw(address indexed user, uint256 lockId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount);

    constructor(address _JOJO, address _USDC) Ownable() {
        JOJO = IERC20(_JOJO);
        USDC = IERC20(_USDC);
    }

    function deposit(uint256 _amount, uint256 _lockTime) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(_lockTime >= REWARD_PERIOD && _lockTime <= MAX_LOCK_TIME, "Lock time must be between 1 week and 4 years");

        JOJO.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 veJOJOAmount = calculateVeJOJO(_amount, _lockTime);

        uint256 lockId = userLockCount[msg.sender];
        userLocks[msg.sender][lockId] = LockInfo({
            amount: _amount,
            end: block.timestamp + _lockTime,
            veJOJOAmount: veJOJOAmount,
            rewardDebt: (veJOJOAmount * accRewardPerShare) / 1e18
        });
        userLockCount[msg.sender]++;

        totalSupply += veJOJOAmount;

        emit Deposit(msg.sender, lockId, _amount, _lockTime, veJOJOAmount);
    }

    function withdraw(uint256 _lockId) external nonReentrant {
        require(_lockId < userLockCount[msg.sender], "Invalid lock ID");
        LockInfo storage userLock = userLocks[msg.sender][_lockId];
        require(block.timestamp >= userLock.end, "Lock period not ended");
        require(userLock.amount > 0, "No locked JOJO");

        uint256 amount = userLock.amount;
        uint256 veJOJOAmount = userLock.veJOJOAmount;
        userLock.amount = 0;
        userLock.end = 0;
        userLock.veJOJOAmount = 0;

        JOJO.safeTransfer(msg.sender, amount);

        totalSupply -= veJOJOAmount;

        emit Withdraw(msg.sender, _lockId, amount);

        uint256 reward = (veJOJOAmount * accRewardPerShare) / 1e18;
        uint256 pending = reward > userLock.rewardDebt ? reward - userLock.rewardDebt : 0;
        if (pending > 0) {
            USDC.safeTransfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }
    }

    function addReward(uint256 _amount) external onlyOwner {
        require(totalSupply > 0, "No veJOJO holders");
        USDC.safeTransferFrom(msg.sender, address(this), _amount);
        
        accRewardPerShare += (_amount * 1e18) / totalSupply;
        
        emit RewardAdded(_amount);
    }

    function claimReward() external nonReentrant {
        uint256 totalReward = pendingReward(msg.sender);
        require(totalReward > 0, "No rewards to claim");
        
        for (uint256 i = 0; i < userLockCount[msg.sender]; i++) {
            LockInfo storage userLock = userLocks[msg.sender][i];
            if (block.timestamp < userLock.end) {
                userLock.rewardDebt = (userLock.veJOJOAmount * accRewardPerShare) / 1e18;
            }
        }
        
        USDC.safeTransfer(msg.sender, totalReward);
        emit RewardClaimed(msg.sender, totalReward);
    }

    function pendingReward(address _user) public view returns (uint256) {
        uint256 totalPending = 0;
        
        for (uint256 i = 0; i < userLockCount[_user]; i++) {
            LockInfo memory userLock = userLocks[_user][i];
            if (block.timestamp < userLock.end) {
                uint256 pending = (userLock.veJOJOAmount * accRewardPerShare / 1e18) - userLock.rewardDebt;
                totalPending += pending;
            }
        }
        
        return totalPending;
    }

    function balanceOf(address _user) public view returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < userLockCount[_user]; i++) {
            LockInfo memory userLock = userLocks[_user][i];
            if (block.timestamp < userLock.end) {
                totalBalance += userLock.veJOJOAmount;
            }
        }
        return totalBalance;
    }

    function calculateVeJOJO(uint256 _amount, uint256 _lockTime) public pure returns (uint256) {
        return (_amount * _lockTime) / MAX_LOCK_TIME;
    }
}
