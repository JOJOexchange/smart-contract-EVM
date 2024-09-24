// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../JOJODealer.sol";
import "../interfaces/IDealer.sol";
import "../interfaces/IPerpetual.sol";
import "../libraries/EIP712.sol";
import "../libraries/Types.sol";
import "../libraries/Trading.sol";
import "../libraries/SignedDecimalMath.sol";
import "../interfaces/internal/IChainlink.sol";
import {Report, IVerifierProxy} from "../oracle/ChainlinkDS.sol";

/// @title JOJO Dynamic Liquidity Reserve
/// @notice This contract manages a liquidity pool for the JOJO trading platform
/// @dev Implements ERC20 for share tokens, includes withdrawal time-lock mechanism
contract JOJODynamicLiquidityReserve is
    ERC20,
    ReentrancyGuard,
    Ownable,
    Pausable
{
    using SafeERC20 for IERC20;
    using SignedDecimalMath for int256;
    using SignedDecimalMath for uint256;

    // Struct to store market-specific parameters
    struct Market {
        bool isSupported;
        uint256 slippage;
        uint256 maxExposure;
        bytes32 feedId;
        uint256 maxReportDelay;
    }

    // Struct to store withdrawal requests
    struct WithdrawRequest {
        address user;
        uint256 shares;
        uint256 requestTime;
        bool isExecuted;
    }

    mapping(address => Market) public markets;
    WithdrawRequest[] public pendingWithdraws;
    mapping(address => uint256) public lockedShares;

    JOJODealer public jojoDealer;
    IERC20 public primaryAsset;
    uint256 public maxLeverage;
    int256 public maxFeeRate;
    uint256 public usdcHeartbeat;
    uint256 public withdrawDelay;
    uint256 public totalPendingShares;

    IVerifierProxy public verifierProxy;
    IChainlink public usdcFeed;
    address public immutable feeTokenAddress;
    address public immutable feeManager;

    /// @notice The maximum total deposit amount allowed in the reserve
    uint256 public maxTotalDeposit;

    /// @notice Event emitted when the max total deposit is updated
    event MaxTotalDepositUpdated(uint256 newMaxTotalDeposit);

    // Events for important state changes
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event WithdrawRequested(
        address indexed user,
        uint256 shares,
        uint256 requestTime
    );
    event WithdrawExecuted(
        address indexed user,
        uint256 shares,
        uint256 amount
    );
    event MarketParametersSet(
        address indexed market,
        bool isSupported,
        uint256 slippage,
        uint256 maxExposure,
        bytes32 feedId,
        uint256 maxReportDelay
    );
    event GlobalParametersSet(uint256 maxLeverage, int256 maxFeeRate);
    event ExternalContractUpdated(string contractName, address newAddress);
    event WithdrawDelayUpdated(uint256 newWithdrawDelay);

    /// @notice Constructor to initialize the JOJODynamicLiquidityReserve
    /// @param name Name of the ERC20 token
    /// @param symbol Symbol of the ERC20 token
    /// @param _jojoDealer Address of the JOJO Dealer contract
    /// @param _primaryAsset Address of the primary asset (e.g., USDC)
    /// @param _verifierProxy Address of the Chainlink verifier proxy
    /// @param _usdcFeed Address of the USDC price feed
    /// @param _usdcHeartbeat Maximum allowed delay for USDC price updates
    /// @param _feeTokenAddress Address of the token used for fees
    /// @param _feeManager Address of the fee manager
    /// @param _initialMaxTotalDeposit Initial maximum total deposit allowed
    /// @param _initialWithdrawDelay Initial withdrawal delay period
    constructor(
        string memory name,
        string memory symbol,
        address _jojoDealer,
        address _primaryAsset,
        address _verifierProxy,
        address _usdcFeed,
        uint256 _usdcHeartbeat,
        address _feeTokenAddress,
        address _feeManager,
        uint256 _initialMaxTotalDeposit,
        uint256 _initialWithdrawDelay
    ) ERC20(name, symbol) {
        jojoDealer = JOJODealer(_jojoDealer);
        primaryAsset = IERC20(_primaryAsset);
        verifierProxy = IVerifierProxy(_verifierProxy);
        usdcFeed = IChainlink(_usdcFeed);
        usdcHeartbeat = _usdcHeartbeat;
        feeTokenAddress = _feeTokenAddress;
        feeManager = _feeManager;
        maxTotalDeposit = _initialMaxTotalDeposit;
        withdrawDelay = _initialWithdrawDelay;
    }

    /// @notice Sets the maximum total deposit allowed in the reserve
    /// @dev Only callable by the contract owner
    /// @param _newMaxTotalDeposit New maximum total deposit value
    function setMaxTotalDeposit(uint256 _newMaxTotalDeposit) external onlyOwner {
        maxTotalDeposit = _newMaxTotalDeposit;
        emit MaxTotalDepositUpdated(_newMaxTotalDeposit);
    }

    /// @notice Deposits primary asset into the reserve
    /// @dev Mints share tokens to the depositor
    /// @param amount Amount of primary asset to deposit
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(
            getTotalValue() + amount <= maxTotalDeposit,
            "Deposit exceeds max total deposit"
        );

        uint256 shares = calculateShares(amount);
        primaryAsset.safeTransferFrom(msg.sender, address(this), amount);
        primaryAsset.approve(address(jojoDealer), amount);
        jojoDealer.deposit(amount, 0, address(this));
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, amount, shares);
    }

    /// @notice Allows users to request a withdrawal of their shares
    /// @param shares Number of shares to withdraw
    /// @dev Initiates a withdrawal request with a time lock
    function requestWithdraw(
        uint256 shares
    ) external nonReentrant whenNotPaused {
        require(shares <= balanceOf(msg.sender), "Insufficient shares");
        require(
            shares <= balanceOf(msg.sender) - lockedShares[msg.sender],
            "Shares are locked"
        );

        pendingWithdraws.push(
            WithdrawRequest({
                user: msg.sender,
                shares: shares,
                requestTime: block.timestamp,
                isExecuted: false
            })
        );

        lockedShares[msg.sender] += shares;
        totalPendingShares += shares;

        emit WithdrawRequested(msg.sender, shares, block.timestamp);
    }

    /// @notice Executes a pending withdrawal request after the time lock period
    /// @param index Index of the withdrawal request in the pendingWithdraws array
    function executeWithdraw(
        uint256 index
    ) external nonReentrant whenNotPaused {
        require(
            index < pendingWithdraws.length,
            "Invalid withdraw request index"
        );
        WithdrawRequest storage request = pendingWithdraws[index];
        require(!request.isExecuted, "Withdraw already executed");
        require(
            msg.sender == request.user || msg.sender == owner(),
            "Not authorized"
        );
        require(
            block.timestamp >= request.requestTime + withdrawDelay,
            "Withdraw delay not met"
        );

        uint256 withdrawAmount = calculateWithdrawAmount(request.shares);
        require(
            checkLeverageAfterWithdraw(withdrawAmount),
            "Leverage too high after withdraw"
        );

        lockedShares[request.user] -= request.shares;
        totalPendingShares -= request.shares;

        jojoDealer.requestWithdraw(address(this), withdrawAmount, 0);

        // Direct withdrawal to user's account
        jojoDealer.executeWithdraw(address(this), request.user, false, "");

        _burn(request.user, request.shares);

        request.isExecuted = true;

        emit WithdrawExecuted(request.user, request.shares, withdrawAmount);
    }

    /// @notice Calculates the total amount of pending withdrawals
    /// @return Total amount of pending withdrawals in primary asset
    function getTotalPendingWithdrawals() public view returns (uint256) {
        return calculateWithdrawAmount(totalPendingShares);
    }

    /// @notice Calculates the amount of primary asset to withdraw for a given number of shares
    /// @param shares Number of shares to calculate withdrawal amount for
    /// @return Amount of primary asset to withdraw
    function calculateWithdrawAmount(
        uint256 shares
    ) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        require(totalSupply > 0, "No shares minted");
        return (shares * getTotalValue()) / totalSupply;
    }

    /// @notice Calculates the number of shares to mint for a given deposit amount
    /// @param amount Amount of primary asset to deposit
    /// @return Number of shares to mint
    function calculateShares(uint256 amount) internal view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return amount;
        }
        return (amount * totalSupply) / getTotalValue();
    }

    /// @notice Checks if leverage is within limits after a withdrawal
    /// @param withdrawAmount Amount to withdraw
    /// @return Whether leverage is within limits
    function checkLeverageAfterWithdraw(
        uint256 withdrawAmount
    ) internal view returns (bool) {
        (int256 netValue, uint256 exposure, , ) = jojoDealer.getTraderRisk(
            address(this)
        );
        int256 remainingValue = netValue - int256(withdrawAmount);
        return uint256(remainingValue) * maxLeverage >= exposure;
    }

    /// @notice Gets the total value of the reserve
    /// @return Total value in primary asset
    function getTotalValue() public view returns (uint256) {
        (int256 netValue, , , ) = jojoDealer.getTraderRisk(address(this));
        return uint256(netValue);
    }

    /// @notice Sets parameters for a specific market
    /// @param market Address of the market
    /// @param isSupported Whether the market is supported
    /// @param slippage Slippage tolerance for the market
    /// @param maxExposure Maximum exposure allowed for the market
    /// @param feedId Chainlink feed ID for the market
    /// @param maxReportDelay Maximum allowed delay for price reports
    function setMarketParameters(
        address market,
        bool isSupported,
        uint256 slippage,
        uint256 maxExposure,
        bytes32 feedId,
        uint256 maxReportDelay
    ) external onlyOwner {
        markets[market] = Market(
            isSupported,
            slippage,
            maxExposure,
            feedId,
            maxReportDelay
        );
        emit MarketParametersSet(
            market,
            isSupported,
            slippage,
            maxExposure,
            feedId,
            maxReportDelay
        );
    }

    /// @notice Sets global parameters for the reserve
    /// @param _maxLeverage Maximum leverage allowed
    /// @param _maxFeeRate Maximum fee rate allowed
    function setGlobalParameters(
        uint256 _maxLeverage,
        int256 _maxFeeRate
    ) external onlyOwner {
        maxLeverage = _maxLeverage;
        maxFeeRate = _maxFeeRate;
        emit GlobalParametersSet(_maxLeverage, _maxFeeRate);
    }

    /// @notice Updates the address of an external contract
    /// @param contractName Name of the contract to update
    /// @param newAddress New address of the contract
    /// @dev This function allows updating external dependencies without redeploying the main contract
    function updateExternalContract(
        string memory contractName,
        address newAddress
    ) external onlyOwner {
        if (
            keccak256(abi.encodePacked(contractName)) ==
            keccak256(abi.encodePacked("jojoDealer"))
        ) {
            jojoDealer = JOJODealer(newAddress);

        } else if (
            keccak256(abi.encodePacked(contractName)) ==
            keccak256(abi.encodePacked("verifierProxy"))
        ) {
            verifierProxy = IVerifierProxy(newAddress);
        } else if (
            keccak256(abi.encodePacked(contractName)) ==
            keccak256(abi.encodePacked("usdcFeed"))
        ) {
            usdcFeed = IChainlink(newAddress);
        } else {
            revert("Invalid contract name");
        }
        emit ExternalContractUpdated(contractName, newAddress);
    }

    /// @notice Pauses the contract
    /// @dev Can only be called by the contract owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Can only be called by the contract owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Validates a signature according to EIP-1271 standard
    /// @dev This function decodes the signature into an order and an unverified report,
    ///      then validates the order hash and checks the order's validity
    /// @param hash The hash of the data to be signed
    /// @param signature The signature bytes, containing the encoded order and unverified report
    /// @return bytes4 The magic value indicating if the signature is valid
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external returns (bytes4) {
        // Decode the signature into an order and an unverified report
        (Types.Order memory order, bytes memory unverifiedReport) = abi.decode(
            signature,
            (Types.Order, bytes)
        );

        // Verify the order hash
        bytes32 domainSeparator = jojoDealer.domainSeparator();
        bytes32 orderHash = EIP712._hashTypedDataV4(
            domainSeparator,
            Trading._structHash(order)
        );
        require(hash == orderHash, "Invalid order hash");

        // Validate the order and return the appropriate magic value
        if (validateOrder(order, unverifiedReport)) {
            return 0x1626ba7e; // EIP-1271 magic value for success
        } else {
            return 0xffffffff; // Failure
        }
    }

    /// @notice Validates an order against various criteria
    /// @dev Checks market support, price feed, exposure limits, leverage, and fee rates
    /// @param order The order to be validated
    /// @param unverifiedReport The unverified price report for the order
    /// @return bool True if the order is valid, false otherwise
    function validateOrder(
        Types.Order memory order,
        bytes memory unverifiedReport
    ) internal returns (bool) {
        // Check if the market is supported
        Market memory market = markets[order.perp];
        require(market.isSupported, "Market not supported");

        // Verify and validate the price report
        Report memory verifiedReport = verifyReport(unverifiedReport);
        require(verifiedReport.feedId == market.feedId, "Invalid feed ID");
        require(
            block.timestamp - verifiedReport.observationsTimestamp <=
                market.maxReportDelay,
            "Report too old"
        );

        // Check if the order price is within acceptable limits
        require(
            checkOrderPrice(order, verifiedReport, market),
            "Price check failed"
        );

        // Get the current mark price from JOJODealer
        uint256 markPrice = jojoDealer.getMarkPrice(order.perp);

        // Calculate new exposure after the trade
        IPerpetual perpetual = IPerpetual(order.perp);
        (int256 currentPaper, ) = perpetual.balanceOf(address(this));
        int256 newPaper = currentPaper + int256(order.paperAmount);

        // Check if the new exposure is within market limits
        require(
            (newPaper.abs() * markPrice) / 1e18 <= market.maxExposure,
            "Exceeds market exposure limit"
        );

        // Check if the leverage after the trade is within limits
        (int256 netValue, uint256 exposure, , ) = jojoDealer.getTraderRisk(
            address(this)
        );
        uint256 exposureAfterTrade = exposure -
            currentPaper.abs().decimalMul(markPrice) +
            newPaper.abs().decimalMul(markPrice);
            
        require(
            netValue.abs() * maxLeverage >= exposureAfterTrade,
            "Leverage too high after trade"
        );

        // Extract and validate fee rates from the order info
        uint256 infoAsUint = uint256(order.info);
        int64 makerFeeRate = int64(uint64(infoAsUint));
        int64 takerFeeRate = int64(uint64(infoAsUint >> 64));

        require(makerFeeRate <= maxFeeRate, "Maker fee rate too high");
        require(takerFeeRate <= maxFeeRate, "Taker fee rate too high");

        return true;
    }

    /// @notice Checks if the order price is within acceptable limits
    /// @dev Calculates max bid and min ask prices considering USDC price and slippage
    /// @param order The order to check
    /// @param verifiedReport The verified price report
    /// @param market The market parameters
    /// @return bool True if the order price is acceptable, false otherwise
    function checkOrderPrice(
        Types.Order memory order,
        Report memory verifiedReport,
        Market memory market
    ) internal view returns (bool) {
        // IMPORTANT: This function assumes:
        // 1. USDC price feed (usdcFeed) returns price with 8 decimals
        // 2. Chainlink Datastream (verifiedReport) uses 18 decimals
        // 3. All calculations are done with 18 decimal precision

        // Get the current USDC price (assumed to be in 8 decimals)
        uint256 usdcPrice = uint256(getUSDCPrice());

        // Calculate max bid and min ask prices with slippage
        // Note: We're dividing by 1e10 to adjust for the difference between
        // Chainlink Datastream's 18 decimals and USDC's 8 decimals
        // And the order price is in 6 decimals as USDC's decimal is 6
        uint256 maxBidPrice = (uint256(uint192(verifiedReport.bid)) *
            (1e18 - market.slippage)) /
            usdcPrice /
            1e22;
        uint256 minAskPrice = (uint256(uint192(verifiedReport.ask)) *
            (1e18 + market.slippage)) /
            usdcPrice /
            1e22;

        // Calculate the order price
        uint256 orderPrice = uint256(
            (int256(order.creditAmount).abs() * 1e18) /
                int256(order.paperAmount).abs()
        );

        // Check if the order price is within limits based on order type (buy or sell)
        if (order.paperAmount > 0) {
            // For buy orders, check against max bid price
            return orderPrice <= maxBidPrice;
        } else {
            // For sell orders, check against min ask price
            return orderPrice >= minAskPrice;
        }
    }

    /// @notice Verifies a price report using the verifier proxy
    /// @dev Calls the external verifier proxy to validate the report
    /// @param unverifiedReport The unverified price report
    /// @return Report The verified and decoded report
    function verifyReport(
        bytes memory unverifiedReport
    ) internal returns (Report memory) {
        // Verify the report using the verifier proxy
        bytes memory verifiedReportData = verifierProxy.verify(
            unverifiedReport,
            abi.encode(feeTokenAddress)
        );
        return abi.decode(verifiedReportData, (Report));
    }

    /// @notice Retrieves the current USDC price from the Chainlink oracle
    /// @dev Checks if the price is not outdated based on the USDC heartbeat
    /// @return int256 The current USDC price
    function getUSDCPrice() internal view returns (int256) {
        // Get the latest round data from the USDC price feed
        (, int256 price, , uint256 updatedAt, ) = usdcFeed.latestRoundData();

        // Ensure the price is not outdated
        require(
            block.timestamp - updatedAt <= usdcHeartbeat,
            "USDC price outdated"
        );

        return price;
    }

    // Override transfer functions to check for locked shares
    /// @notice Overrides the ERC20 transfer function to check for locked shares
    /// @param recipient Address receiving the tokens
    /// @param amount Amount of tokens to transfer
    /// @return Boolean indicating whether the transfer was successful
    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(
            balanceOf(_msgSender()) - lockedShares[_msgSender()] >= amount,
            "Transfer amount exceeds unlocked balance"
        );
        return super.transfer(recipient, amount);
    }

    /// @notice Overrides the ERC20 transferFrom function to check for locked shares
    /// @param sender Address sending the tokens
    /// @param recipient Address receiving the tokens
    /// @param amount Amount of tokens to transfer
    /// @return Boolean indicating whether the transfer was successful
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(
            balanceOf(sender) - lockedShares[sender] >= amount,
            "Transfer amount exceeds unlocked balance"
        );
        return super.transferFrom(sender, recipient, amount);
    }

    /// @notice Sets the withdraw delay
    /// @dev Only the contract owner can call this function
    /// @param _newWithdrawDelay The new withdraw delay
    function setWithdrawDelay(uint256 _newWithdrawDelay) external onlyOwner {
        withdrawDelay = _newWithdrawDelay;
        emit WithdrawDelayUpdated(_newWithdrawDelay);
    }
}
