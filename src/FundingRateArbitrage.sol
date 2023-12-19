/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./JOJODealer.sol";
import "./interfaces/IPerpetual.sol";
import "./interfaces/IJUSDBank.sol";
import "./libraries/SignedDecimalMath.sol";

pragma solidity ^0.8.9;

struct WithdrawalRequest {
    uint256 earnUSDCAmount;
    address user;
    bool isExecuted;
}

contract FundingRateArbitrage is Ownable {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

    address public immutable collateral;
    address public immutable jusdBank;
    address public immutable jojoDealer;
    address public immutable perpMarket;
    address public immutable usdc;
    address public immutable jusd;

    uint256 public maxNetValue;
    uint256 public totalEarnUSDCBalance;
    uint256 public depositFeeRate;
    uint256 public withdrawFeeRate;
    uint256 public withdrawSettleFee;

    mapping(address => uint256) public earnUSDCBalance;
    mapping(address => uint256) public jusdOutside;

    WithdrawalRequest[] public withdrawalRequests;

    // Event
    event DepositToHedging(
        address from,
        uint256 USDCAmount,
        uint256 feeAmount,
        uint256 earnUSDCAmount
    );

    event RequestWithdrawFromHedging(
        address from,
        uint256 RepayJUSDAmount,
        uint256 withdrawEarnUSDCAmount,
        uint256 index
    );

    event PermitWithdraw(
        address from,
        uint256 USDCAmount,
        uint256 feeAmount,
        uint256 earnUSDCAmount,
        uint256 index
    );

    event Swap(
        address fromToken,
        address toToken,
        uint256 payAmount,
        uint256 receivedAmount
    );

    constructor(
        address _collateral,
        address _jusdBank,
        address _jojoDealer,
        address _perpMarket,
        address _Operator
    ) Ownable() {
        collateral = _collateral;
        jusdBank = _jusdBank;
        jojoDealer = _jojoDealer;
        perpMarket = _perpMarket;
        (address USDC, address JUSD, , , , , ) = JOJODealer(jojoDealer).state();
        usdc = USDC;
        jusd = JUSD;
        JOJODealer(jojoDealer).setOperator(_Operator, true);
        IERC20(collateral).approve(jusdBank, type(uint256).max);
        IERC20(jusd).approve(jusdBank, type(uint256).max);
        IERC20(jusd).approve(jojoDealer, type(uint256).max);
        IERC20(usdc).approve(jojoDealer, type(uint256).max);
    }

    // View
    function getNetValue() public view returns (uint256) {
        uint256 jusdBorrowed = IJUSDBank(jusdBank).getBorrowBalance(
            address(this)
        );
        uint256 collateralAmount = IJUSDBank(jusdBank).getDepositBalance(
            collateral,
            address(this)
        );
        uint256 usdcBuffer = IERC20(usdc).balanceOf(address(this));
        uint256 collateralPrice = IJUSDBank(jusdBank).getCollateralPrice(
            collateral
        );
        (int256 perpNetValue, , , ) = JOJODealer(jojoDealer).getTraderRisk(
            address(this)
        );
        return
            SafeCast.toUint256(perpNetValue) +
            collateralAmount.decimalMul(collateralPrice) +
            usdcBuffer -
            jusdBorrowed;
    }

    function getIndex() public view returns (uint256) {
        if (totalEarnUSDCBalance == 0) {
            return 1e18;
        } else {
            // getNetValue = 4020
            return SignedDecimalMath.decimalDiv(getNetValue(), totalEarnUSDCBalance);
        }
    }

    function buildSpotSwapData(
        address approveTarget,
        address swapTarget,
        uint256 payAmount,
        bytes memory callData
    ) public pure returns (bytes memory spotTradeParam) {
        spotTradeParam = abi.encode(
            approveTarget,
            swapTarget,
            payAmount,
            callData
        );
    }

    //Only Owner
    function setOperator(address operator, bool isValid) public onlyOwner {
        JOJODealer(jojoDealer).setOperator(operator, isValid);
    }

    function setMaxNetValue(uint256 newMaxNetValue) public onlyOwner {
        maxNetValue = newMaxNetValue;
    }

    function setDepositFeeRate(uint256 newDepositFeeRate) public onlyOwner {
        depositFeeRate = newDepositFeeRate;
    }

    function setWithdrawFeeRate(uint256 newWithdrawFeeRate) public onlyOwner {
        withdrawFeeRate = newWithdrawFeeRate;
    }

    function setWithdrawSettleFee(
        uint256 newWithdrawSettleFee
    ) public onlyOwner {
        withdrawSettleFee = newWithdrawSettleFee;
    }

    function refundJUSD(uint256 amount) public onlyOwner {
        IERC20(jusd).safeTransfer(msg.sender, amount);
    }

    function swapBuyWstETH(
        uint256 minReceivedCollateral,
        bytes memory spotTradeParam
    ) public onlyOwner {
        uint256 receivedCollateral = _swap(spotTradeParam, true);
        require(receivedCollateral >= minReceivedCollateral, "SWAP SLIPPAGE");
        _depositToJUSDBank(IERC20(collateral).balanceOf(address(this)));
    }

    function swapSellWstEth(
        uint256 minReceivedUSDC,
        uint256 collateralAmount,
        bytes memory spotTradeParam
    ) public onlyOwner {
        _withdrawFromJUSDBank(collateralAmount);
        uint256 receivedUSDC = _swap(spotTradeParam, false);
        require(receivedUSDC >= minReceivedUSDC, "SWAP SLIPPAGE");
    }

    function borrow(uint256 JUSDAmount) public onlyOwner {
        _borrowJUSD(JUSDAmount);
    }

    function repay(uint256 JUSDRebalanceAmount) public onlyOwner {
        JOJODealer(jojoDealer).fastWithdraw(
            address(this),
            address(this),
            0,
            JUSDRebalanceAmount,
            false,
            ""
        );
        _repayJUSD(JUSDRebalanceAmount);
    }

    function _swap(
        bytes memory param,
        bool isBuyingWsteth
    ) private returns (uint256 receivedAmount) {
        address fromToken;
        address toToken;
        if (isBuyingWsteth) {
            fromToken = usdc;
            toToken = collateral;
        } else {
            fromToken = collateral;
            toToken = usdc;
        }
        uint256 toTokenReserve = IERC20(toToken).balanceOf(address(this));
        (
            address approveTarget,
            address swapTarget,
            uint256 payAmount,
            bytes memory callData
        ) = abi.decode(param, (address, address, uint256, bytes));
        IERC20(fromToken).safeApprove(approveTarget, payAmount);
        (bool isSuccess, ) = swapTarget.call(callData);
        if (!isSuccess) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        receivedAmount =
            IERC20(toToken).balanceOf(address(this)) -
            toTokenReserve;
        emit Swap(fromToken, toToken, payAmount, receivedAmount);
    }

    // JUSDBank Operations
    function _borrowJUSD(uint256 JUSDAmount) internal {
        IJUSDBank(jusdBank).borrow(JUSDAmount, address(this), true);
    }

    function _repayJUSD(uint256 amount) internal {
        IJUSDBank(jusdBank).repay(amount, address(this));
    }

    function _withdrawFromJUSDBank(uint256 amount) internal {
        IJUSDBank(jusdBank).withdraw(collateral, amount, address(this), false);
    }

    function _depositToJUSDBank(uint256 amount) internal {
        IJUSDBank(jusdBank).deposit(
            address(this),
            collateral,
            amount,
            address(this)
        );
    }

    // JOJODealer Operations
    function depositUSDCToPerp(uint256 primaryAmount) public onlyOwner {
        JOJODealer(jojoDealer).deposit(primaryAmount, 0, address(this));
    }

    function fastWithdrawUSDCFromPerp(uint256 primaryAmount) public onlyOwner {
        JOJODealer(jojoDealer).fastWithdraw(
            address(this),
            address(this),
            primaryAmount,
            0,
            false,
            ""
        );
    }

    // LP Functions
    function deposit(uint256 amount) external {
        require(amount != 0, "deposit amount is zero");
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
        uint256 feeAmount = amount.decimalMul(depositFeeRate);
        if (feeAmount > 0) {
            amount -= feeAmount;
            IERC20(usdc).transfer(owner(), feeAmount);
        }
        JOJODealer(jojoDealer).deposit(amount, 0, msg.sender);
        uint256 earnUSDCAmount = amount.decimalDiv(getIndex());
        earnUSDCBalance[msg.sender] += earnUSDCAmount;
        jusdOutside[msg.sender] += amount;
        totalEarnUSDCBalance += earnUSDCAmount;
        require(getNetValue() <= maxNetValue, "net value exceed limitation");
        emit DepositToHedging(msg.sender, amount, feeAmount, earnUSDCAmount);
    }

    function requestWithdraw(
        uint256 repayJUSDAmount
    ) external returns (uint256 withdrawEarnUSDCAmount) {
        IERC20(jusd).safeTransferFrom(
            msg.sender,
            address(this),
            repayJUSDAmount
        );
        require(
            repayJUSDAmount <= jusdOutside[msg.sender],
            "Request Withdraw too big"
        );
        jusdOutside[msg.sender] -= repayJUSDAmount;
        uint256 index = getIndex();
        uint256 lockedEarnUSDCAmount = jusdOutside[msg.sender].decimalDiv(
            index
        );
        require(earnUSDCBalance[msg.sender] >= lockedEarnUSDCAmount, "lockedEarnUSDCAmount is bigger than earnUSDCBalance");
        withdrawEarnUSDCAmount =
            earnUSDCBalance[msg.sender] -
            lockedEarnUSDCAmount;
        withdrawalRequests.push(
            WithdrawalRequest(withdrawEarnUSDCAmount, msg.sender, false)
        );
        require(
            withdrawEarnUSDCAmount.decimalMul(index) >= withdrawSettleFee,
            "Withdraw amount is smaller than settleFee"
        );
        earnUSDCBalance[msg.sender] = lockedEarnUSDCAmount;
        uint256 withdrawIndex = withdrawalRequests.length - 1;
        emit RequestWithdrawFromHedging(
            msg.sender,
            repayJUSDAmount,
            withdrawEarnUSDCAmount,
            withdrawIndex
        );
        return withdrawIndex;
    }

    function permitWithdrawRequests(
        uint256[] memory requestIDList
    ) external onlyOwner {
        uint256 index = getIndex();
        for (uint256 i; i < requestIDList.length; i++) {
            WithdrawalRequest storage request = withdrawalRequests[
                requestIDList[i]
            ];
            require(!request.isExecuted, "request has been executed");
            uint256 USDCAmount = request.earnUSDCAmount.decimalMul(index);
            uint256 feeAmount = (USDCAmount - withdrawSettleFee).decimalMul(
                withdrawFeeRate
            ) + withdrawSettleFee;
            if (feeAmount > 0) {
                IERC20(usdc).transfer(owner(), feeAmount);
            }
            IERC20(usdc).transfer(request.user, USDCAmount - feeAmount);
            request.isExecuted = true;
            totalEarnUSDCBalance -= request.earnUSDCAmount;
            emit PermitWithdraw(
                request.user,
                USDCAmount,
                feeAmount,
                request.earnUSDCAmount,
                requestIDList[i]
            );
        }
    }
}
