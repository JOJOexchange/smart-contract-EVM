# JOJO: Decentralized Perpetual Contract Exchange

JOJO is a decentralized perpetual contract exchange based on an off-chain matching system that can be divided into three key components: trading, collateral lending, and funding rate arbitrage.

## What is a Perpetual Contract?

A perpetual contract is a financial derivative where participants buy and sell virtual notes, typically anchored to an external reference like the "price of Bitcoin." JOJO utilizes a funding rate mechanism to align the contract price with the spot price, offering traders increased liquidity and leverage compared to the spot market.

## Trading System

There are only two core smart contracts: [Perpetual.sol](./src/Perpetual.sol) and [JOJODealer.sol](./src/JOJODealer.sol).

- `Perpetual.sol` is the core balance sheet of a certain perpetual contract market.
- `JOJODealer.sol` owns `Perpetual.sol`. One `JOJODealer.sol` may have several `Perpetual.sol` simultaneously.

### Perpetual.sol: The Balance Sheet

For traders, their balance consists of paper (asset quantity) and credit. The combination of these two values forms their balance. Both paper and credit can be negative.

Example:

- Long 1BTC at $30,000:

```javascript
paper = 1;
credit = -30000;
```

- Short 1BTC at $30,000:

```javascript
paper = -1;
credit = 30000;
```

The essence of the perpetual contract calculation is the state transfer of balance. Luckily, there are only three types of operations that affect balance.

1. Funding rate
2. Trading
3. Liquidation

#### Funding Rate

The funding rate ensures the perpetual contract price aligns with the spot price. Two scenarios guide its adjustments:

- When the contract price exceeds the spot price, the long side is penalized, and the short side is rewarded. This prompts a decrease in the contract price until it matches the spot price.
- Conversely, if the contract price is lower than the spot price, the short side is penalized, and the long side is rewarded, increasing the contract price to match the spot price.

To manage credit adjustments based on paper, a value named "reducedCredit" is recorded. The actual credit is calculated using the formula:

`credit = (paper * fundingRate) + reducedCredit`

This mechanism ensures each trader's credit is automatically adjusted according to changes in the fundingRate, which can be positive or negative. An increase in the fundingRate facilitates the movement of funds from short to long positions, whereas a decrease prompts a shift from long to short positions. These fundingRate updates, managed by the JOJO team, take place every 8 hours.

To check balances, utilize the function:

```javascript
function balanceOf(address trader)
        external
        view
        returns (int256 paper, int256 credit);
```

#### Trading

A relayer acts as the order sender, gathering orders from both makers and takers, matching them, and then submitting them to the perpetual contract using the `trade` function. Only verified addresses are permitted to be order senders.

The validation and computation processes are handled within the `approveTrade` in [JOJOExternal.sol](./src/JOJOExternal.sol). Given the complexity of this matter, we won't delve into further details.

#### Liquidation

Liquidation is a mandatory trading behavior. You can trigger a liquidation by calling the function below:

```javascript
function liquidate(
    address liquidator,
    address liquidatedTrader,
    int256 requestPaper,
    int256 expectCredit
) external returns (int256 liqtorPaperChange, int256 liqtorCreditChange)
```

Like trading, we leave it to [JOJOExternal.sol](./src/JOJOExternal.sol).

### JOJODealer.sol: Dealer of the Table

Responsible for maintaining funding rates, executing trades, and managing liquidations.

Features:

- Off-chain matching, on-chain settlement.
- Cross model for shared margin across positions.
- Fixed discount liquidation.

#### Trading

The JOJODealer leverages an order book model for liquidity provision, enabling off-chain order placement, cancellation, and matching, with final settlements conducted on-chain.

Users generate signed orders and transmit them to JOJO's server. Upon order matching, JOJO's server promptly submits these orders to the blockchain and instantly notifies users via the front end.

The only centralized aspect is the JOJO server's deletion of order information and signatures upon user order cancellations. However, users can mitigate risk by opting for orders with very short expiration times, reducing reliance on trusting the JOJO server.

Moreover, anyone can match orders, and the individual who submits the matching result to the blockchain earns trading fees.

Refer to `approveTrade` in [JOJOExternal.sol](./src/JOJOExternal.sol). for implementation details.

#### Cross Mode

JOJODealer only offers a cross-position mode, where positions under different markets share margin. Positions under either market will affect the account's net value and global exposure.

See `getTraderRisk` in [JOJOView.sol](./src/JOJOView.sol).

If you wish to use the isolated mode, switch wallets or create sub-accounts.

#### Fixed Discount Liquidation

JOJODealer will sell their positions at a fixed discount for accounts with low margin rates. Anyone can take as many positions as they want if the position is cleared or the account margin rate is healthy.

See `getLiquidationCost` in [JOJOView.sol](./src/JOJOView.sol).

#### Deposit Margin

JOJODealer only accepts USDC and JUSD as margin. Deposits and withdrawals do not require permission from the JOJO server.

#### Withdraw Margin

We have two withdrawal modes: pending withdrawal and fast withdrawal. In fast withdrawal, users can withdraw their margin in one step. If the `fastWithdrawDisabled` is turned on, the user does not support fast withdrawals. Users need to wait for timelock to get their margin, and users withdraw funds in two steps(`requestWithdraw` and `exewcuteWithdraw`), separated by a waiting period of no more than one minute.

### Subaccount

We use a specially designed contract as a trading account, and the user's wallet address is the owner of this contract. This design can free users from changing their wallet address, and also an easy way for other protocols to build on JOJO. Subaccounts can help their owner manage risk and positions. Users can open orders with isolated positions via Subaccount, and can also let others trade for you by setting them as authorized operators.

See `newSubaccount()` in [SubaccountFactory.sol](./src/subaccount/SubaccountFactory.sol).

## Lending System

There are only one core smart contracts: [JUSDBank.sol](./src/JUSDBank.sol).

- `JUSDBank.sol` is the core accounting sheet of the whole collateral lending system and contains all "external" functions.

### JUSD

JUSD is a stablecoin developed by the JOJO system to support multi-collateralization. JUSD works like DAI, and users can mint JUSD using other ERC20 tokens as collateral. Then, JUSD can deposit to the trading system as a position margin. The `secondaryAsset` in the trading system is referred to as JUSD.

### JUSDBank.sol: Core Accounting Sheet

Manages the collateral lending system, allowing users to borrow JUSD using deposited collateral.

Features:

- Manage to loan JUSD
- Flash loans for immediate transactions.

#### Loan

Within the lending system, users can deposit approved collateral using the deposit function and subsequently borrow JUSD via the borrow function. Following their trading activities, users can repay the borrowed JUSD by invoking the repay function, facilitating the retrieval of their collateral through the withdraw function.

In cases where the value of borrowed JUSD exceeds the total value of deposited collaterals, a trader becomes susceptible to liquidation. The initial liquidation formula is determined by the equation:

`JUSDBorrow > sum(deposit amount * price * liquidationMortgageRate)`

#### Flashloan

Flash Loans in JOJO enable the withdrawal of an asset within a single transaction, provided the account remains secure until the transaction ends. Users aren't required to repay JUSD before initiating the transaction.

Two lending system examples include:

- FlashLoanRepay.sol: Enables JUSD repayment using deposited collateral.
- FlashLoanLiquidate.sol: Involves liquidating collateral, distributing resulting USDC into three parts: JUSD repayment, insurance payment, and, if there's surplus, transferring it as USDC to the liquidated party.

## Funding Rate Arbitrage

The core contract [FundingRateArbitrage](./src/FundingRateArbitrage.sol) involves offsetting trades in both spot and perpetual markets to capture funding rate income in perpetual trading.

Key functions:

- LPs can deposit USDC into the arbitrage pool via the deposit function, earning interest. Withdrawal requests for both interest and capital can be made by users, executed within 24 hours through permitWithdrawRequests.
- Upon users depositing USDC into the arbitrage pool, the admin utilizes the USDC to purchase ETH and deposits it into the JUSDBank system via the swapBuyEth function. Subsequently, the admin borrows JUSD using borrow and deposits it into the trading system. Finally, the admin initiates short interest in the trading system to accumulate funding fees.

## Other Components

- **Index price & Mark price:** Obtained from third-party price oracles.
- **Insurance:** Charged for liquidations, covering bad debts and utilizing insurance funds.

## Commands

### Install

```shell
$ forge install
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## License

The primary license for JOJO smart contract EVM is the Business Source License 1.1 (BUSL-1.1), see LICENSE. Minus the following exceptions:

- Some script have a GPL license
