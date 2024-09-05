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
    }

    struct RewardInfo {
        uint256 lastClaimTime;
        uint256 rewardDebt;
    }

    mapping(address => mapping(uint256 => LockInfo)) public userLocks;
    mapping(address => uint256) public userLockCount;
    mapping(address => RewardInfo) public userRewards;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;
    uint256 public constant REWARD_PERIOD = 7 days;

    uint256 private constant MAX_LOCK_TIME = 4 * 365 days;

    event Deposit(address indexed user, uint256 lockId, uint256 amount, uint256 lockTime, uint256 veJOJOAmount);
    event Withdraw(address indexed user, uint256 lockId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount);

    constructor(address _JOJO, address _USDC) Ownable() {
        JOJO = IERC20(_JOJO);
        USDC = IERC20(_USDC);
        lastRewardTime = block.timestamp;
    }

    function deposit(uint256 _amount, uint256 _lockTime) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(_lockTime >= 7 days && _lockTime <= MAX_LOCK_TIME, "Lock time must be between 1 week and 4 years");

        updateReward(msg.sender);

        JOJO.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 veJOJOAmount = calculateVeJOJO(_amount, _lockTime);

        uint256 lockId = userLockCount[msg.sender];
        userLocks[msg.sender][lockId] = LockInfo({
            amount: _amount,
            end: block.timestamp + _lockTime,
            veJOJOAmount: veJOJOAmount
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

        updateReward(msg.sender);

        uint256 amount = userLock.amount;
        uint256 veJOJOAmount = userLock.veJOJOAmount;
        userLock.amount = 0;
        userLock.end = 0;
        userLock.veJOJOAmount = 0;

        JOJO.safeTransfer(msg.sender, amount);

        totalSupply -= veJOJOAmount;

        emit Withdraw(msg.sender, _lockId, amount);
    }

    function claimReward() external nonReentrant {
        updateReward(msg.sender);
        uint256 reward = pendingReward(msg.sender);
        if (reward > 0) {
            userRewards[msg.sender].rewardDebt += reward;
            USDC.safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function addReward(uint256 _amount) external onlyOwner {
        updateReward(address(0));
        USDC.safeTransferFrom(msg.sender, address(this), _amount);
        emit RewardAdded(_amount);
    }

    function updateReward(address _user) public {
        if (block.timestamp > lastRewardTime) {
            uint256 usdcReward = USDC.balanceOf(address(this));
            if (totalSupply > 0 && usdcReward > 0) {
                accRewardPerShare += (usdcReward * 1e18) / totalSupply;
            }
            lastRewardTime = block.timestamp;
        }
        if (_user != address(0)) {
            RewardInfo storage userReward = userRewards[_user];
            userReward.rewardDebt = pendingReward(_user);
            userReward.lastClaimTime = block.timestamp;
        }
    }

    function pendingReward(address _user) public view returns (uint256) {
        RewardInfo memory userReward = userRewards[_user];
        uint256 pending = (balanceOf(_user) * accRewardPerShare / 1e18) - userReward.rewardDebt;
        return pending;
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

    // ... 其他函数 ...
}
