/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IJUSDBank.sol";
import "./interfaces/IFlashLoanReceive.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/internal/IPriceSource.sol";
import "./JUSDOperation.sol";
import "./JUSDView.sol";
import "./JUSDBankStorage.sol";
import "./JUSDMulticall.sol";

contract JUSDBank is IJUSDBank, JUSDOperation, JUSDView, JUSDMulticall {
    using SignedDecimalMath for uint256;
    using SafeERC20 for IERC20;

    constructor(
        uint256 _maxReservesNum,
        address _insurance,
        address _JUSD,
        address _JOJODealer,
        uint256 _maxPerAccountBorrowAmount,
        uint256 _maxTotalBorrowAmount,
        uint256 _borrowFeeRate,
        address _primaryAsset
    ) {
        maxReservesNum = _maxReservesNum;
        JUSD = _JUSD;
        JOJODealer = _JOJODealer;
        insurance = _insurance;
        maxPerAccountBorrowAmount = _maxPerAccountBorrowAmount;
        maxTotalBorrowAmount = _maxTotalBorrowAmount;
        borrowFeeRate = _borrowFeeRate;
        tRate = Types.ONE;
        primaryAsset = _primaryAsset;
        lastUpdateTimestamp = uint32(block.timestamp);
    }

    // Event

    event Deposit(
        address indexed collateral, address indexed from, address indexed to, address operator, uint256 amount
    );

    event Borrow(address indexed from, address indexed to, uint256 amount, bool isDepositToJOJO);

    event Repay(address indexed from, address indexed to, uint256 amount);

    event Withdraw(
        address indexed collateral, address indexed from, address indexed to, uint256 amount, bool ifInternal
    );

    event Liquidate(
        address indexed collateral,
        address indexed liquidator,
        address indexed liquidated,
        address operator,
        uint256 collateralAmount,
        uint256 liquidatedAmount,
        uint256 insuranceFee
    );

    event FlashLoan(address indexed collateral, uint256 amount);

    event HandleBadDebt(address indexed liquidatedTrader, uint256 borrowJUSDT0);

    // Modifier

    modifier isValidOperator(address operator, address client) {
        require(msg.sender == client || operatorRegistry[client][operator], Errors.CAN_NOT_OPERATE_ACCOUNT);
        _;
    }

    modifier isLiquidator(address liquidator) {
        if (isLiquidatorWhitelistOpen) {
            require(isLiquidatorWhiteList[liquidator], "liquidator is not in the liquidator white list");
        }
        _;
    }

    // Function

    /// @inheritdoc IJUSDBank
    function deposit(
        address from,
        address collateral,
        uint256 amount,
        address to
    )
        external
        override
        nonReentrant
        isValidOperator(msg.sender, from)
    {
        Types.ReserveInfo storage reserve = reserveInfo[collateral];
        Types.UserInfo storage user = userInfo[to];
        _deposit(reserve, user, amount, collateral, to, from);
    }

    /// @inheritdoc IJUSDBank
    function borrow(
        uint256 amount,
        address to,
        bool isDepositToJOJO
    )
        external
        override
        nonReentrant
        nonFlashLoanReentrant
    {
        Types.UserInfo storage user = userInfo[msg.sender];
        accrueRate();
        _borrow(user, isDepositToJOJO, to, amount, msg.sender);
        require(_isAccountSafe(user, tRate), Errors.AFTER_BORROW_ACCOUNT_IS_NOT_SAFE);
    }

    /// @inheritdoc IJUSDBank
    function repay(uint256 amount, address to) external override nonReentrant returns (uint256) {
        Types.UserInfo storage user = userInfo[to];
        accrueRate();
        return _repay(user, msg.sender, to, amount, tRate);
    }

    /// @inheritdoc IJUSDBank
    function withdraw(
        address collateral,
        uint256 amount,
        address to,
        bool isInternal
    )
        external
        override
        nonReentrant
        nonFlashLoanReentrant
    {
        Types.UserInfo storage user = userInfo[msg.sender];
        _withdraw(amount, collateral, to, msg.sender, isInternal);
        uint256 tRate = getTRate();
        require(_isAccountSafe(user, tRate), Errors.AFTER_WITHDRAW_ACCOUNT_IS_NOT_SAFE);
    }

    /// @inheritdoc IJUSDBank
    function liquidate(
        address liquidated,
        address collateral,
        address liquidator,
        uint256 amount,
        bytes memory afterOperationParam,
        uint256 expectPrice
    )
        external
        override
        isValidOperator(msg.sender, liquidator)
        nonFlashLoanReentrant
        returns (Types.LiquidateData memory liquidateData)
    {
        accrueRate();
        uint256 JUSDBorrowedT0 = userInfo[liquidated].t0BorrowBalance;
        uint256 primaryLiquidatedAmount = IERC20(primaryAsset).balanceOf(address(this));
        uint256 primaryInsuranceAmount = IERC20(primaryAsset).balanceOf(insurance);
        isValidLiquidator(liquidated, liquidator);

        {
            Types.UserInfo storage liquidatedInfo = userInfo[liquidated];
            require(amount != 0, Errors.LIQUIDATE_AMOUNT_IS_ZERO);
            if (amount >= liquidatedInfo.depositBalance[collateral]) {
                amount = liquidatedInfo.depositBalance[collateral];
            }
        }

        liquidateData = _calculateLiquidateAmount(liquidated, collateral, amount);
        require(
            // condition: actual liquidate price < max buy price,
            (liquidateData.insuranceFee + liquidateData.actualLiquidated).decimalDiv(liquidateData.actualCollateral)
                <= expectPrice,
            Errors.LIQUIDATION_PRICE_PROTECTION
        );

        _afterLiquidateOperation(afterOperationParam, amount, collateral, liquidated, liquidateData);

        require(
            JUSDBorrowedT0 - userInfo[liquidated].t0BorrowBalance >= liquidateData.actualLiquidatedT0,
            Errors.REPAY_AMOUNT_NOT_ENOUGH
        );
        require(
            IERC20(primaryAsset).balanceOf(insurance) - primaryInsuranceAmount >= liquidateData.insuranceFee,
            Errors.INSURANCE_AMOUNT_NOT_ENOUGH
        );
        require(
            IERC20(primaryAsset).balanceOf(address(this)) - primaryLiquidatedAmount
                >= liquidateData.liquidatedRemainUSDC,
            Errors.LIQUIDATED_AMOUNT_NOT_ENOUGH
        );
        IERC20(primaryAsset).safeTransfer(liquidated, liquidateData.liquidatedRemainUSDC);
        emit Liquidate(
            collateral,
            liquidator,
            liquidated,
            msg.sender,
            liquidateData.actualCollateral,
            liquidateData.actualLiquidated,
            liquidateData.insuranceFee
        );
    }

    /// @inheritdoc IJUSDBank
    function handleDebt(address[] calldata liquidatedTraders) external onlyOwner {
        for (uint256 i; i < liquidatedTraders.length; i = i + 1) {
            _handleBadDebt(liquidatedTraders[i]);
        }
    }

    /// @inheritdoc IJUSDBank
    function flashLoan(
        address receiver,
        address collateral,
        uint256 amount,
        address to,
        bytes memory param
    )
        external
        nonFlashLoanReentrant
    {
        Types.UserInfo storage user = userInfo[msg.sender];
        _withdraw(amount, collateral, receiver, msg.sender, false);
        IFlashLoanReceive(receiver).JOJOFlashLoan(collateral, amount, to, param);
        require(_isAccountSafe(user, getTRate()), Errors.AFTER_FLASHLOAN_ACCOUNT_IS_NOT_SAFE);
        emit FlashLoan(collateral, amount);
    }

    function refundJUSD(uint256 amount) external onlyOwner {
        IERC20(JUSD).safeTransfer(msg.sender, amount);
    }

    // Internal

    function _deposit(
        Types.ReserveInfo storage reserve,
        Types.UserInfo storage user,
        uint256 amount,
        address collateral,
        address to,
        address from
    )
        internal
    {
        require(reserve.isDepositAllowed, Errors.RESERVE_NOT_ALLOW_DEPOSIT);
        require(amount != 0, Errors.DEPOSIT_AMOUNT_IS_ZERO);
        IERC20(collateral).safeTransferFrom(from, address(this), amount);
        _addCollateralIfNotExists(user, collateral);
        user.depositBalance[collateral] += amount;
        reserve.totalDepositAmount += amount;
        require(
            user.depositBalance[collateral] <= reserve.maxDepositAmountPerAccount,
            Errors.EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT
        );
        require(reserve.totalDepositAmount <= reserve.maxTotalDepositAmount, Errors.EXCEED_THE_MAX_DEPOSIT_AMOUNT_TOTAL);
        emit Deposit(collateral, from, to, msg.sender, amount);
    }

    function _borrow(
        Types.UserInfo storage user,
        bool isDepositToJOJO,
        address to,
        uint256 tAmount,
        address from
    )
        internal
    {
        uint256 t0Amount = tAmount.decimalRemainder(tRate) ? tAmount.decimalDiv(tRate) : tAmount.decimalDiv(tRate) + 1;
        user.t0BorrowBalance += t0Amount;
        t0TotalBorrowAmount += t0Amount;
        if (isDepositToJOJO) {
            IERC20(JUSD).approve(address(JOJODealer), tAmount);
            IDealer(JOJODealer).deposit(0, tAmount, to);
        } else {
            IERC20(JUSD).safeTransfer(to, tAmount);
        }
        require(
            user.t0BorrowBalance.decimalMul(tRate) <= maxPerAccountBorrowAmount,
            Errors.EXCEED_THE_MAX_BORROW_AMOUNT_PER_ACCOUNT
        );
        require(
            t0TotalBorrowAmount.decimalMul(tRate) <= maxTotalBorrowAmount, Errors.EXCEED_THE_MAX_BORROW_AMOUNT_TOTAL
        );
        emit Borrow(from, to, tAmount, isDepositToJOJO);
    }

    function _repay(
        Types.UserInfo storage user,
        address payer,
        address to,
        uint256 amount,
        uint256 tRate
    )
        internal
        returns (uint256)
    {
        require(amount != 0, Errors.REPAY_AMOUNT_IS_ZERO);
        uint256 JUSDBorrowed = user.t0BorrowBalance.decimalMul(tRate);
        uint256 tBorrowAmount;
        uint256 t0Amount;
        if (JUSDBorrowed <= amount) {
            tBorrowAmount = JUSDBorrowed;
            t0Amount = user.t0BorrowBalance;
        } else {
            tBorrowAmount = amount;
            t0Amount = amount.decimalDiv(tRate);
        }
        IERC20(JUSD).safeTransferFrom(payer, address(this), tBorrowAmount);
        user.t0BorrowBalance -= t0Amount;
        t0TotalBorrowAmount -= t0Amount;
        emit Repay(payer, to, tBorrowAmount);
        return tBorrowAmount;
    }

    function _withdraw(uint256 amount, address collateral, address to, address from, bool isInternal) internal {
        Types.ReserveInfo storage reserve = reserveInfo[collateral];
        Types.UserInfo storage fromAccount = userInfo[from];
        require(amount != 0, Errors.WITHDRAW_AMOUNT_IS_ZERO);
        require(amount <= fromAccount.depositBalance[collateral], Errors.WITHDRAW_AMOUNT_IS_TOO_BIG);
        fromAccount.depositBalance[collateral] -= amount;
        if (isInternal) {
            require(reserve.isDepositAllowed, Errors.RESERVE_NOT_ALLOW_DEPOSIT);
            Types.UserInfo storage toAccount = userInfo[to];
            _addCollateralIfNotExists(toAccount, collateral);
            toAccount.depositBalance[collateral] += amount;
            require(
                toAccount.depositBalance[collateral] <= reserve.maxDepositAmountPerAccount,
                Errors.EXCEED_THE_MAX_DEPOSIT_AMOUNT_PER_ACCOUNT
            );
        } else {
            reserve.totalDepositAmount -= amount;
            IERC20(collateral).safeTransfer(to, amount);
        }
        emit Withdraw(collateral, from, to, amount, isInternal);
        _removeEmptyCollateral(fromAccount, collateral);
    }

    function isValidLiquidator(address liquidated, address liquidator) internal view {
        require(liquidator != liquidated, Errors.SELF_LIQUIDATION_NOT_ALLOWED);
        if (isLiquidatorWhitelistOpen) {
            require(isLiquidatorWhiteList[liquidator], Errors.LIQUIDATOR_NOT_IN_THE_WHITELIST);
        }
    }

    function _calculateLiquidateAmount(
        address liquidated,
        address collateral,
        uint256 amount
    )
        internal
        view
        returns (Types.LiquidateData memory liquidateData)
    {
        Types.UserInfo storage liquidatedInfo = userInfo[liquidated];
        require(_isStartLiquidation(liquidatedInfo, tRate), Errors.ACCOUNT_IS_SAFE);
        Types.ReserveInfo memory reserve = reserveInfo[collateral];
        uint256 price = IPriceSource(reserve.oracle).getAssetPrice();
        uint256 priceOff = price.decimalMul(Types.ONE - reserve.liquidationPriceOff);
        uint256 liquidateAmount = amount.decimalMul(priceOff).decimalMul(Types.ONE - reserve.insuranceFeeRate);
        uint256 JUSDBorrowed = liquidatedInfo.t0BorrowBalance.decimalMul(tRate);
        /*
            liquidateAmount <= JUSDBorrowed
            liquidateAmount = amount * priceOff * (1-insuranceFee)
            actualJUSD = actualCollateral * priceOff
            insuranceFee = actualCollateral * priceOff * insuranceFeeRate
        */
        if (liquidateAmount <= JUSDBorrowed) {
            liquidateData.actualCollateral = amount;
            liquidateData.insuranceFee = amount.decimalMul(priceOff).decimalMul(reserve.insuranceFeeRate);
            liquidateData.actualLiquidatedT0 = liquidateAmount.decimalDiv(tRate);
            liquidateData.actualLiquidated = liquidateAmount;
        } else {
            /*
                actualJUSD
                    = actualCollateral * priceOff
                    = JUSDBorrowed * priceOff / priceOff * (1-insuranceFeeRate)
                    = JUSDBorrowed / (1-insuranceFeeRate)
                    = insuranceFee = actualJUSD * insuranceFeeRate
                    = actualCollateral * priceOff * insuranceFeeRate
                    = JUSDBorrowed * insuranceFeeRate / (1- insuranceFeeRate)
            */
            liquidateData.actualCollateral =
                JUSDBorrowed.decimalDiv(priceOff).decimalDiv(Types.ONE - reserve.insuranceFeeRate);
            liquidateData.insuranceFee =
                JUSDBorrowed.decimalMul(reserve.insuranceFeeRate).decimalDiv(Types.ONE - reserve.insuranceFeeRate);
            liquidateData.actualLiquidatedT0 = liquidatedInfo.t0BorrowBalance;
            liquidateData.actualLiquidated = JUSDBorrowed;
        }

        liquidateData.liquidatedRemainUSDC = (amount - liquidateData.actualCollateral).decimalMul(price);
    }

    function _addCollateralIfNotExists(Types.UserInfo storage user, address collateral) internal {
        if (!user.hasCollateral[collateral]) {
            user.hasCollateral[collateral] = true;
            user.collateralList.push(collateral);
        }
    }

    function _removeEmptyCollateral(Types.UserInfo storage user, address collateral) internal {
        if (user.depositBalance[collateral] == 0) {
            user.hasCollateral[collateral] = false;
            address[] storage collaterals = user.collateralList;
            for (uint256 i; i < collaterals.length; i = i + 1) {
                if (collaterals[i] == collateral) {
                    collaterals[i] = collaterals[collaterals.length - 1];
                    collaterals.pop();
                    break;
                }
            }
        }
    }

    function _afterLiquidateOperation(
        bytes memory afterOperationParam,
        uint256 flashloanAmount,
        address collateral,
        address liquidated,
        Types.LiquidateData memory liquidateData
    )
        internal
    {
        (address flashloanAddress, bytes memory param) = abi.decode(afterOperationParam, (address, bytes));
        _withdraw(flashloanAmount, collateral, flashloanAddress, liquidated, false);
        param = abi.encode(liquidateData, param);
        IFlashLoanReceive(flashloanAddress).JOJOFlashLoan(collateral, flashloanAmount, liquidated, param);
    }

    function _handleBadDebt(address liquidatedTrader) internal {
        Types.UserInfo storage liquidatedTraderInfo = userInfo[liquidatedTrader];
        uint256 tRate = getTRate();
        if (liquidatedTraderInfo.collateralList.length == 0 && _isStartLiquidation(liquidatedTraderInfo, tRate)) {
            Types.UserInfo storage insuranceInfo = userInfo[insurance];
            uint256 borrowJUSDT0 = liquidatedTraderInfo.t0BorrowBalance;
            insuranceInfo.t0BorrowBalance += borrowJUSDT0;
            liquidatedTraderInfo.t0BorrowBalance = 0;
            emit HandleBadDebt(liquidatedTrader, borrowJUSDT0);
        }
    }
}
