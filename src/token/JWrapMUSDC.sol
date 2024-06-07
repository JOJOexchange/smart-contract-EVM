/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@moonwell/MToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../JOJODealer.sol";
import "../libraries/SignedDecimalMath.sol";
import "../interfaces/internal/IPriceSource.sol";
import "../interfaces/IJUSDBank.sol";

pragma solidity ^0.8.19;

interface IMUSDCController {
    function claimReward(address holder, MToken[] memory mTokens) external;
}

interface IMUSDC {
    function mint(uint256 amount) external;
}

contract JWrapMUSDC is Ownable, ERC20 {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

    address public immutable usdc;
    address public immutable well;
    address public immutable controller;
    address public immutable mUSDC;
    address public immutable jusdBank;

    uint256 public rewardAdd;
    uint256 public totalDeposit;
    mapping(address => uint256) mUSDCUserTotalDeposit;
    mapping(address => uint256) mUSDCUserTotalWithdraw;

    // Event
    event DepositMUSDC(address from, uint256 mUSDCAmount, uint256 jWrapMUSDCAmount);

    event WithdrawMUSDC(address from, uint256 jWrapMUSDCAmount, uint256 mUSDCAmount);

    event SwapToken(address fromToken, address toToken, uint256 payAmount, uint256 receivedAmount);

    constructor(
        address _mUSDC,
        address _usdc,
        address _controller,
        address _well,
        address _jusdBank
    )
        Ownable()
        ERC20("jWrapMUSDC", "jWrapMUSDC")
    {
        mUSDC = _mUSDC;
        usdc = _usdc;
        controller = _controller;
        well = _well;
        jusdBank = _jusdBank;
    }

    // View
    function getIndex() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        } else {
            return SignedDecimalMath.decimalDiv(totalDeposit + rewardAdd, totalSupply());
        }
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }
    
    function buildSpotSwapData(
        address approveTarget,
        address swapTarget,
        bytes memory callData
    )
        external
        pure
        returns (bytes memory spotTradeParam)
    {
        spotTradeParam = abi.encode(approveTarget, swapTarget, callData);
    }

    function refundMUSDC() external onlyOwner {
        IERC20(mUSDC).safeTransfer(owner(), IERC20(mUSDC).balanceOf(address(this)) - totalDeposit - rewardAdd);
    } 

    function claimReward() public onlyOwner returns(uint256) {
        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = MToken(mUSDC);
        IMUSDCController(controller).claimReward(address(this), mTokens);
        return IERC20(well).balanceOf(address(this));
    }

    function swapWellToUSDC(uint256 amount, uint256 minReceivedUSDC, bytes memory param) public onlyOwner {
        (address approveTarget, address swapTarget, bytes memory callData) =
            abi.decode(param, (address, address, bytes));
        require(swapTarget != mUSDC, "swapTartget is not mUSDC address");
        IERC20(well).safeApprove(approveTarget, 0);
        IERC20(well).safeApprove(approveTarget, amount);
        uint256 usdcReserve = IERC20(usdc).balanceOf(address(this));
        (bool isSuccess,) = swapTarget.call(callData);
        if (!isSuccess) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        uint256 receivedAmount = IERC20(usdc).balanceOf(address(this)) - usdcReserve;
        require(receivedAmount >= minReceivedUSDC, "SWAP SLIPPAGE");
        emit SwapToken(well, usdc, amount, receivedAmount);
    }

    function swapUSDCToMUSDC() public onlyOwner {
        uint256 mUSDCReserve = IERC20(mUSDC).balanceOf(address(this));
        uint256 usdcAmount = IERC20(usdc).balanceOf(address(this));
        IERC20(usdc).approve(address(mUSDC), usdcAmount);
        IMUSDC(mUSDC).mint(usdcAmount);
        uint256 receivedAmount = IERC20(mUSDC).balanceOf(address(this)) - mUSDCReserve;
        rewardAdd += receivedAmount;
        emit SwapToken(usdc, mUSDC, usdcAmount, receivedAmount);
    }

    function claimRewardAndSwap(uint256 amount, uint256 minReceivedUSDC, bytes memory param) public onlyOwner {
        claimReward();
        swapWellToUSDC(amount, minReceivedUSDC, param);
        swapUSDCToMUSDC();
    }

    // LP Functions
    function deposit(uint256 amount) public {
        IERC20(mUSDC).safeTransferFrom(msg.sender, address(this), amount);
        uint256 jWrapMUSDCAmount = amount.decimalDiv(getIndex());
        _mint(msg.sender, jWrapMUSDCAmount);
        mUSDCUserTotalDeposit[msg.sender] += amount;
        totalDeposit += amount;
        emit DepositMUSDC(msg.sender, amount, jWrapMUSDCAmount);
    }

    function wrapAndDeposit(uint256 amount) external {
        IERC20(mUSDC).safeTransferFrom(msg.sender, address(this), amount);
        uint256 jWrapMUSDCAmount = amount.decimalDiv(getIndex());
        _mint(address(this), jWrapMUSDCAmount);
        mUSDCUserTotalDeposit[msg.sender] += amount;
        totalDeposit += amount;
        IERC20(address(this)).approve(jusdBank, jWrapMUSDCAmount);
        IJUSDBank(jusdBank).deposit(address(this), address(this), jWrapMUSDCAmount, msg.sender);
        emit DepositMUSDC(msg.sender, amount, jWrapMUSDCAmount);
    }

    function withdraw(uint256 jWrapMUSDCAmount) external returns(uint256) {
        uint256 mUSDCAmount = jWrapMUSDCAmount.decimalMul(getIndex());
        mUSDCUserTotalWithdraw[msg.sender] += mUSDCAmount;
        totalDeposit -= mUSDCAmount;
        _burn(msg.sender, jWrapMUSDCAmount);
        IERC20(mUSDC).safeTransfer(msg.sender, mUSDCAmount);
        emit WithdrawMUSDC(msg.sender, jWrapMUSDCAmount, mUSDCAmount);
        return mUSDCAmount;
    }
}
