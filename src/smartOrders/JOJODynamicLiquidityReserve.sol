// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../JOJODealer.sol";
import "../interfaces/IDealer.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/EIP712.sol";
import "../libraries/Types.sol";
import "../libraries/Trading.sol";
import "../libraries/SignedDecimalMath.sol";
import "../interfaces/internal/IChainlink.sol";
import {Report, IVerifierProxy} from "../oracle/ChainlinkDS.sol";

contract JOJODynamicLiquidityReserve is ERC20, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for int256;
    using SignedDecimalMath for uint256;
    using SafeMath for uint256;

    struct Market {
        bool isSupported;
        uint256 slippage;
        uint256 maxExposure;
        bytes32 feedId;
        uint256 decimalCorrection;
        uint256 maxReportDelay;
    }
    mapping(address => Market) public markets;

    JOJODealer public jojoDealer;
    IERC20 public primaryAsset;
    uint256 public maxLeverage;
    int256 public maxFeeRate;
    uint256 public usdcHeartbeat;

    IVerifierProxy public verifierProxy;
    IChainlink public usdcFeed;
    address public immutable feeTokenAddress;
    address public immutable feeManager;

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    constructor(
        string memory _name,
        string memory _symbol,
        address _jojoDealer,
        address _primaryAsset,
        address _verifierProxy,
        address _usdcFeed,
        uint256 _usdcHeartbeat,
        address _feeTokenAddress,
        address _feeManager
    ) ERC20(_name, _symbol) {
        jojoDealer = JOJODealer(_jojoDealer);
        primaryAsset = IERC20(_primaryAsset);
        verifierProxy = IVerifierProxy(_verifierProxy);
        usdcFeed = IChainlink(_usdcFeed);
        usdcHeartbeat = _usdcHeartbeat;
        feeTokenAddress = _feeTokenAddress;
        feeManager = _feeManager;

        // Approve feeManager to spend unlimited amount of feeTokenAddress
        IERC20(feeTokenAddress).approve(feeManager, type(uint256).max);
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external returns (bytes4) {
        // 解析订单数据和未经验证的 Chainlink DS report
        (Types.Order memory order, bytes memory unverifiedReport) = abi.decode(
            signature,
            (Types.Order, bytes)
        );

        // 验证 hash
        bytes32 domainSeparator = jojoDealer.domainSeparator();
        bytes32 orderHash = EIP712._hashTypedDataV4(
            domainSeparator,
            Trading._structHash(order)
        );
        require(hash == orderHash, "Invalid order hash");

        // 验证订单
        if (validateOrder(order, unverifiedReport)) {
            return 0x1626ba7e; // EIP-1271 magic value for success
        } else {
            return 0xffffffff; // Failure
        }
    }

    function validateOrder(
        Types.Order memory order,
        bytes memory unverifiedReport
    ) internal returns (bool) {
        Market memory market = markets[order.perp];
        require(market.isSupported, "Market not supported");

        // 验证 Chainlink DS report
        Report memory verifiedReport = verifyReport(unverifiedReport);
        require(verifiedReport.feedId == market.feedId, "Invalid feed ID");
        require(
            block.timestamp - verifiedReport.observationsTimestamp <=
                market.maxReportDelay,
            "Report too old"
        );

        // 检查价格
        require(
            checkOrderPrice(order, verifiedReport, market),
            "Price check failed"
        );

        // 检查风险敞口
        // 获取 JOJODealer 中的 markPrice
        uint256 markPrice = jojoDealer.getMarkPrice(order.perp);

        IPerpetual perpetual = IPerpetual(order.perp);
        (int256 currentPaper, ) = perpetual.balanceOf(address(this));
        int256 newPaper = currentPaper + int256(order.paperAmount);
        require(
            (newPaper.abs() * markPrice) / 1e18 <= market.maxExposure,
            "Exceeds market exposure limit"
        );

        (int256 netValue, uint256 exposure, , ) = jojoDealer.getTraderRisk(
            address(this)
        );
        uint256 exposureAfterTrade = exposure -
            currentPaper.abs().decimalMul(markPrice) +
            newPaper.abs().decimalMul(markPrice) /
            1e18;
        require(
            netValue.abs().decimalMul(maxLeverage) >= exposureAfterTrade,
            "Leverage too high after trade"
        );

        // 从 info 中解析费率
        uint256 infoAsUint = uint256(order.info);
        int64 makerFeeRate = int64(uint64(infoAsUint));
        int64 takerFeeRate = int64(uint64(infoAsUint >> 64));

        // 检查费率
        require(makerFeeRate <= maxFeeRate, "Maker fee rate too high");
        require(takerFeeRate <= maxFeeRate, "Taker fee rate too high");

        return true;
    }

    function checkOrderPrice(
        Types.Order memory order,
        Report memory verifiedReport,
        Market memory market
    ) internal view returns (bool) {
        // 获取 USDC-USD 价格
        uint256 usdcPrice = uint256(getUSDCPrice());
        uint256 maxBidPrice = (uint256(uint192(verifiedReport.bid)) *
            (1e18 - market.slippage)) /
            usdcPrice /
            1e10;
        uint256 minAskPrice = (uint256(uint192(verifiedReport.ask)) *
            (1e18 + market.slippage)) /
            usdcPrice /
            1e10;

        // 查订单价格是否在允许范围内
        uint256 orderPrice = uint256(
            (int256(order.creditAmount).abs() * 1e18) /
                int256(order.paperAmount).abs()
        );

        if (order.paperAmount > 0) {
            // 买单
            return orderPrice <= maxBidPrice;
        } else {
            // 卖单
            return orderPrice >= minAskPrice;
        }
    }

    function verifyReport(
        bytes memory unverifiedReport
    ) internal returns (Report memory) {
        // Verify the report
        bytes memory verifiedReportData = verifierProxy.verify(
            unverifiedReport,
            abi.encode(feeTokenAddress)
        );
        
        return abi.decode(verifiedReportData, (Report));
    }

    function getUSDCPrice() internal view returns (int256) {
        (, int256 price, , uint256 updatedAt, ) = usdcFeed.latestRoundData();
        require(
            block.timestamp - updatedAt <= usdcHeartbeat,
            "USDC price outdated"
        );
        return price;
    }

    function setMarketParameters(
        address market,
        bool isSupported,
        uint256 slippage,
        uint256 maxExposure,
        bytes32 feedId,
        uint256 decimalCorrection,
        uint256 maxReportDelay
    ) external onlyOwner {
        markets[market] = Market(
            isSupported,
            slippage,
            maxExposure,
            feedId,
            decimalCorrection,
            maxReportDelay
        );
    }

    function setGlobalParameters(
        uint256 _maxLeverage,
        int256 _maxFeeRate
    ) external onlyOwner {
        maxLeverage = _maxLeverage;
        maxFeeRate = _maxFeeRate;
    }

    function deposit(uint256 amount) external nonReentrant {
        uint256 shares = calculateShares(amount);
        primaryAsset.safeTransferFrom(msg.sender, address(this), amount);
        primaryAsset.approve(address(jojoDealer), amount);
        jojoDealer.deposit(amount, 0, address(this));
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external nonReentrant {
        require(shares <= balanceOf(msg.sender), "Insufficient shares");
        uint256 amount = calculateWithdrawAmount(shares);
        require(
            checkLeverageAfterWithdraw(amount),
            "Leverage too high after withdraw"
        );
        jojoDealer.requestWithdraw(address(this), amount, 0);
        jojoDealer.executeWithdraw(address(this), msg.sender, true, "");
        _burn(msg.sender, shares);
        emit Withdraw(msg.sender, amount, shares);
    }

    function calculateShares(uint256 amount) internal view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return amount;
        }
        return (amount * totalSupply) / getTotalValue();
    }

    function calculateWithdrawAmount(
        uint256 shares
    ) internal view returns (uint256) {
        return (shares * getTotalValue()) / totalSupply();
    }

    function checkLeverageAfterWithdraw(
        uint256 withdrawAmount
    ) internal view returns (bool) {
        (int256 netValue, uint256 exposure, , ) = jojoDealer.getTraderRisk(
            address(this)
        );
        int256 remainingValue = netValue - int256(withdrawAmount);
        return uint256(remainingValue) * maxLeverage >= exposure;
    }

    function getTotalValue() public view returns (uint256) {
        (int256 netValue, , , ) = jojoDealer.getTraderRisk(address(this));
        return uint256(netValue);
    }
}
