/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./JOJODealer.sol";
import "./interfaces/IPerpetual.sol";
import "./interfaces/IJUSDBank.sol";
import "./libraries/SignedDecimalMath.sol";

pragma solidity ^0.8.19;

/// @notice This contract involves offsetting trades in both the spot and perpetual contract markets
/// to capture the funding rate income in perpetual contract trading. Liquidy provider can deposit usdc
/// to this pool and accumulate interest.
contract FundingRateArbitrage is Ownable, ERC20 {
    struct WithdrawalRequest {
        uint256 perpUSDCAmount;
        address user;
        bool isExecuted;
    }

    using SafeERC20 for IERC20;
    using SignedDecimalMath for uint256;

    address public immutable collateral;
    address public immutable jojoDealer;
    address public immutable perpMarket;
    address public immutable usdc;
    address public immutable jusd;

    uint256 public maxNetValue;
    uint256 public depositFeeRate;
    uint256 public withdrawFeeRate;
    uint256 public withdrawSettleFee;
    uint256 public defaultUsdcQuota;
    uint256 public minimumWithdraw;
    mapping(address => uint256) public maxUsdcQuota;

    WithdrawalRequest[] public withdrawalRequests;

    // Event
    event DepositToHedging(address from, uint256 USDCAmount, uint256 feeAmount, uint256 perpUSDCAmount);

    event RequestWithdrawFromHedging(address from, uint256 perpUSDCAmount, uint256 index);

    event PermitWithdraw(address from, uint256 USDCAmount, uint256 feeAmount, uint256 perpUSDCAmount, uint256 index);

    event Swap(address fromToken, address toToken, uint256 payAmount, uint256 receivedAmount);

    constructor(
        address _collateral,
        address _jojoDealer,
        address _perpMarket,
        address _Operator
    )
        ERC20("PerpUSDC", "PerpUSDC")
        Ownable()
    {
        collateral = _collateral;
        jojoDealer = _jojoDealer;
        perpMarket = _perpMarket;
        (address USDC, address JUSD,,,,,) = JOJODealer(jojoDealer).state();
        usdc = USDC;
        jusd = JUSD;
        JOJODealer(jojoDealer).setOperator(_Operator, true);
        IERC20(jusd).approve(jojoDealer, type(uint256).max);
        IERC20(usdc).approve(jojoDealer, type(uint256).max);
    }

    // View

    /// @notice this function is to return the sum of netValue in whole system.
    /// including the netValue in collateral system, trading system and buffer usdc
    function getNetValue() public view returns (uint256) {
        uint256 collateralAmount = IERC20(collateral).balanceOf(address(this));
        uint256 usdcBuffer = IERC20(usdc).balanceOf(address(this));
        uint256 collateralPrice = JOJODealer(jojoDealer).getMarkPrice(perpMarket);
        (int256 perpNetValue,,,) = JOJODealer(jojoDealer).getTraderRisk(address(this));
        (, uint256 jusdAmount,,,) = JOJODealer(jojoDealer).getCreditOf(address(this));
        return SafeCast.toUint256(perpNetValue) + collateralAmount.decimalMul(collateralPrice) + usdcBuffer - jusdAmount;
    }

    function getIndex() public view returns (uint256) {
        return SignedDecimalMath.decimalDiv(getNetValue() + 1, totalSupply() + 1e12);
    }

    function buildSpotSwapData(
        address approveTarget,
        address swapTarget,
        uint256 payAmount,
        bytes memory callData
    )
        public
        pure
        returns (bytes memory spotTradeParam)
    {
        spotTradeParam = abi.encode(approveTarget, swapTarget, payAmount, callData);
    }

    //Only Owner

    /// @notice this function is to set Operator who can operate this pool
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

    function setDefaultQuota(uint256 defaultQuota) public onlyOwner {
        defaultUsdcQuota = defaultQuota;
    }

    /// @notice this function is to set the personal deposit quota
    function setPersonalQuota(address to, uint256 personalQuota) public onlyOwner {
        maxUsdcQuota[to] = personalQuota;
    }

    function setWithdrawSettleFee(uint256 newWithdrawSettleFee) public onlyOwner {
        withdrawSettleFee = newWithdrawSettleFee;
    }

    function setMinimumWithdraw(uint256 _minimumWithdraw) public onlyOwner {
        minimumWithdraw = _minimumWithdraw;
    }

    /// @notice this function is to swap usdc to eth and deposit to collateral system
    /// @param minReceivedCollateral is the minimum eth received
    /// @param spotTradeParam is param to swap usdc to eth, can build by this function: `buildSpotSwapData`
    function swapBuyEth(uint256 minReceivedCollateral, bytes memory spotTradeParam) public onlyOwner {
        uint256 receivedCollateral = _swap(spotTradeParam, true);
        require(receivedCollateral >= minReceivedCollateral, "SWAP SLIPPAGE");
    }

    /// @notice this function is to withdraw eth to the pool and swap eth to usdc
    /// @param minReceivedUSDC is the minimum usdc received
    /// @param spotTradeParam is param to swap eth to usdc, can build by this function: `buildSpotSwapData`
    function swapSellEth(uint256 minReceivedUSDC, bytes memory spotTradeParam) public onlyOwner {
        uint256 receivedUSDC = _swap(spotTradeParam, false);
        require(receivedUSDC >= minReceivedUSDC, "SWAP SLIPPAGE");
    }

    function _swap(bytes memory param, bool isBuyingEth) private returns (uint256 receivedAmount) {
        address fromToken;
        address toToken;
        if (isBuyingEth) {
            fromToken = usdc;
            toToken = collateral;
        } else {
            fromToken = collateral;
            toToken = usdc;
        }
        uint256 toTokenReserve = IERC20(toToken).balanceOf(address(this));
        (address approveTarget, address swapTarget, uint256 payAmount, bytes memory callData) =
            abi.decode(param, (address, address, uint256, bytes));
        IERC20(fromToken).safeApprove(approveTarget, 0);
        IERC20(fromToken).safeApprove(approveTarget, payAmount);
        (bool isSuccess,) = swapTarget.call(callData);
        if (!isSuccess) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        receivedAmount = IERC20(toToken).balanceOf(address(this)) - toTokenReserve;
        emit Swap(fromToken, toToken, payAmount, receivedAmount);
    }

    // JOJODealer Operations
    /// @notice this function is to deposit the buffered usdc from pool to trading system
    /// @param primaryAmount is the expected deposit primary amount.
    function depositUSDCToPerp(uint256 primaryAmount) public onlyOwner {
        JOJODealer(jojoDealer).deposit(primaryAmount, 0, address(this));
    }

    /// @notice this function is to withdraw the buffered usdc from trading system to pool
    /// @param primaryAmount is the expected withdraw primary amount.
    function fastWithdrawUSDCFromPerp(uint256 primaryAmount) public onlyOwner {
        JOJODealer(jojoDealer).fastWithdraw(address(this), address(this), primaryAmount, 0, false, "");
    }

    function fastWithdrawJUSDFromPerp(uint256 secondaryAmount) public onlyOwner {
        JOJODealer(jojoDealer).fastWithdraw(address(this), address(this), 0, secondaryAmount, false, "");
        IERC20(jusd).safeTransfer(msg.sender, secondaryAmount);
    }

    // LP Functions

    /// @notice this function is called by liquidity providers, users can deposit usdc to arbitrage
    /// @dev During the deposit, users usdc will transfer to the system and system will return
    /// the equivalent amount of jusd which deposit to the trading system.
    /// @param amount is the expected deposit usdc amount.
    function deposit(uint256 amount) external {
        require(amount != 0, "deposit amount is zero");
        require(
            amount.decimalMul(Types.ONE - depositFeeRate) > withdrawSettleFee,
            "The deposit amount is less than the minimum withdrawal amount"
        );
        uint256 feeAmount = amount.decimalMul(depositFeeRate);
        if (feeAmount > 0) {
            amount -= feeAmount;
            IERC20(usdc).safeTransferFrom(msg.sender, owner(), feeAmount);
        }
        uint256 perpUSDCAmount = amount.decimalDiv(getIndex());
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, perpUSDCAmount);
        require(getNetValue() <= maxNetValue, "net value exceed limitation");
        uint256 quota = maxUsdcQuota[msg.sender] == 0 ? defaultUsdcQuota : maxUsdcQuota[msg.sender];
        require(balanceOf(msg.sender).decimalMul(getIndex()) <= quota, "usdc amount bigger than quota");
        emit DepositToHedging(msg.sender, amount, feeAmount, perpUSDCAmount);
    }

    /// @notice this function is to submit a withdrawal which wiil permit by our system in 24 hours
    /// The main purpose of this function is to capture the interest and avoid the DOS attacks.
    /// @dev users need to withdraw jusd from trading system firstly or by jusd, then transfer jusd to
    /// the pool and get usdc back
    function requestWithdraw(uint256 perpUSDCAmount) external returns (uint256) {
        IERC20(address(this)).safeTransferFrom(msg.sender, address(this), perpUSDCAmount);
        uint256 index = getIndex();
        withdrawalRequests.push(WithdrawalRequest(perpUSDCAmount, msg.sender, false));
        require(perpUSDCAmount.decimalMul(index) >= minimumWithdraw, "Withdraw amount is smaller than minimumWithdraw");
        require(perpUSDCAmount.decimalMul(index) >= withdrawSettleFee, "Withdraw amount is smaller than settleFee");
        uint256 withdrawIndex = withdrawalRequests.length - 1;
        emit RequestWithdrawFromHedging(msg.sender, perpUSDCAmount, withdrawIndex);
        return withdrawIndex;
    }

    /// @notice this function is to permit withdrawals which are submit by liqudity provider
    /// @param requestIDList is the request ids
    function permitWithdrawRequests(uint256[] memory requestIDList) external onlyOwner {
        uint256 index = getIndex();
        for (uint256 i; i < requestIDList.length; i++) {
            WithdrawalRequest storage request = withdrawalRequests[requestIDList[i]];
            require(!request.isExecuted, "request has been executed");
            uint256 USDCAmount = request.perpUSDCAmount.decimalMul(index);
            require(USDCAmount >= withdrawSettleFee, "USDCAmount need to bigger than withdrawSettleFee");
            uint256 feeAmount = (USDCAmount - withdrawSettleFee).decimalMul(withdrawFeeRate) + withdrawSettleFee;
            if (feeAmount > 0) {
                IERC20(usdc).safeTransfer(owner(), feeAmount);
            }
            IERC20(usdc).safeTransfer(request.user, USDCAmount - feeAmount);
            request.isExecuted = true;
            _burn(address(this), request.perpUSDCAmount);
            emit PermitWithdraw(request.user, USDCAmount, feeAmount, request.perpUSDCAmount, requestIDList[i]);
        }
    }
}