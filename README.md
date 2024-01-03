# JOJO

JOJO is a decentralized perpetual contract exchange based on an off-chain matching system that can be divided into three parts: trading part, collateral lending part, and arbitrage part. 

# What is a perpetual contract

A perpetual contract is simply a group of people who buy and sell virtual notes (also known as financial derivatives). In principle, the price of a note can be arbitrary. But through the mechanism of *funding rate*, it can be anchored to an external number, such as the "price of Bitcoin". 

In this way, trading such notes is very similar to trading bitcoin spot. Since the liquidity of such a note is independent of spot liquidity, it can achieve liquidity and leverage multiples that far exceed those of the spot market. This feature has made perpetual contracts the most popular derivative in the cryptocurrency market.


# JOJO code overview

We will walk you through a comprehensive understanding of the whole JOJO system. 

We don't expect this readme to explain the entire contract system. We just want to show you where to find the corresponding code for each function. There are enough comments in the code to explain all the details.

There are three parts in the JOJO system, let us discuss them separately.

# Trading system
There are only two core smart contracts: [Perpetual.sol](./src/Perpetual.sol) & [JOJODealer.sol](./src/JOJODealer.sol).

- `Perpetual.sol` is the core balance sheet of a certain perpetual contract market.
- `JOJODealer.sol` is the owner of `Perpetual.sol`. One `JOJODealer.sol` may have several `Perpetual.sol` at the same time.
- `JOJODealer.sol` is separated into [JOJOView.sol](./src/JOJOView.sol), [JOJOOperation.sol](./src/JOJOOperation.sol), and [JOJOExternal.sol](./src/JOJOExternal.sol).
- `JOJOView.sol` contains all view functions of `JOJODealer.sol`.
- `JOJOOperation.sol` contains all "onlyOwner" functions of `JOJODealer.sol`.
- `JOJOExternal.sol` contains all "external" functions of `JOJODealer.sol`.
- [JOJOStorage.sol](./src/JOJOStorage.sol) is where all data stored.

## Perpetual.sol: The balance sheet

From now on, we are going to design a perpetual contract computing system on the blockchain, which is referred to as [Perpetual.sol](./src/Perpetual.sol)

For a trader, we only need to maintain the number of *paper* and *credit* s/he holds. Both the number of *paper* and the number of *credits* can be negative. We call the combination of these two numbers "balance".

If a trader long 1BTC at 30,000USD, then his balance is

```javascript
paper = 1
credit = -30000
```

If a trader shorts 1BTC at 30,000USD, then his balance is

```javascript
paper = -1
credit = 30000
```

The essence of the perpetual contract calculation is the state transfer of balance. Luckily, there are only 3 types of operations that affect balance.

1. Funding rate
2. Trading
3. Liquidation

### Funding rate

It is the dealer's responsibility to ensure that the perpetual contract price is anchored to the spot price. Using the funding rate is one of the most common ways to achieve that.

- If the contract price is higher than the spot, the dealer should punish the long side and reward the short side. So the contract price decreases until it equals the spot price.
- If the contract price is lower than the spot, the dealer should punish the short side and reward the long side. So the contract price increases until it equals the spot price.

The funding rate adjusts *credit* according to the *paper* amount. It is impossible to record the number of credits on the chain, otherwise, it would be too costly to modify thousands of credit values each time the funding rate is updated. So we record a value called "reducedCredit" on the chain, and the real credit is calculated using the following formula:

`credit = (paper * fundingRate) + reducedCredit`

In this way, each trader's credit is automatically updated each time *fundingRate* is updated. *fundingRate* can be positive or negative. When *fundingRate* increases, the dealer could transfer funds from short positions to long positions. When *fundingRate* decreases, the dealer could transfer from long positions to short positions.

JOJO team will update the *fundingRate* every 8 hours.

You can call the function below to check your paper and credit balances:

```javascript
function balanceOf(address trader)
        external
        view
        returns (int256 paper, int256 credit);
```

However, we must point out that we use the cross model, so the balance under a single market does not reflect your risk level. Please refer to `getTraderRisk` in [JOJOView.sol](./src/JOJOView.sol).

### Trading

An order sender is a relayer. He collects orders from makers and takers, matches, and submits to the perpetual contract via function `trade`. 

For now, to avoid endless expansion of systemic risk, only validated addresses can be order senders.

We leave all the validation and calculations in `approveTrade` [JOJOExternal.sol](./src/JOJOExternal.sol). This is a complex issue so we will not dive deeper. 

### Liquidation

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

So far we have successfully defined the core Perpetual contract. Next, we will solve the outstanding issues one by one.

## JOJODealer.sol: Dealer of the table

Just as there is a dealer at the table, there is a moderator in the perpetual contract game. The dealer is the owner of the perpetual, it is responsible for solving all the problems that the perpetual does not know how to do. A dealer can have more than one perpetual at a time.

The dealer has three main responsibilities:

1. Maintain funding rate
2. Trade
3. Execute liquidation

The Dealer can be designed in various ways, and JOJODealerV1.0 is just one of the solutions proposed by the JOJO team. For example, you can develop an AMM version of Dealer.

JOJODealer has four main features below: 

- Off-chain matching, on-chain settlement
- Cross model
- Fixed discount liquidation
- Virtual credit

### Trading: Off-chain matching, on-chain settlement

JOJODealer uses the order book model to provide liquidity. Orders are placed, canceled, and matched off-chain, while the final settlement occurs on-chain. This architecture is similar to 0xProtocol, which allows for an excellent trading experience while keeping the system decentralized enough.

It is implemented by users signing orders and sending them to JOJO's server. Whenever orders are matched, JOJO's server submits these orders to the blockchain and immediately notifies the user on the front end.

The only centralized thing is that: the JOJO server will delete order info and signature when a user cancels an order. However, users may choose to place orders with very short expiration times to de-risk the need for trusting the JOJO server.

In addition, anyone can match orders, and whoever submits the matching result to the blockchain receives trading fees.

See `approveTrade` in [JOJOExternal.sol](./src/JOJOExternal.sol).

### Cross mode

JOJODealer only offers a cross-position mode, where positions under different markets share margin. Positions under either market will affect the account's net value and global exposure.

See `getTraderRisk` in [JOJOView.sol](./src/JOJOView.sol).

If you wish to use the isolated mode, you could simply switch wallets or create sub-accounts.

### Fixed discount liquidation

For accounts with low margin rates, JOJODealer will sell their positions at a fixed discount. Anyone can take as many positions as they want, as long as the position is cleared or the account margin rate is at a healthy state.

See `getLiquidationCost` in [JOJOView.sol](./src/JOJOView.sol).

### Deposit margin

JOJODealer only accepts USDC and JUSD as margin. Deposits and withdrawals do not require the permission of the JOJO server.

### Pending withdraw

To save time for the matching engine to cancel orders when users withdraw, user withdrawals need to be submitted in two steps, with a waiting period in between (no more than 1 minute).

### Virtual credit

JOJO can grant credit to some accounts to temporarily obtain more margin. This design has two main purposes:

- Supporting multi-margin features in the future
- Matching funds to market makers in exchange for better liquidity

# Lending system
There are only two core smart contracts: [JUSDBank.sol](./src/JUSDBank.sol) and [JUSDExchange.sol](./src/JUSDExchange.sol)

- `JUSDBank.sol` is the core accounting sheet of the whole collateral lending system and contains all "external" functions.
- `JUSDBank.sol` is separated into [JUSDOperation.sol](./src/JUSDOperation.sol), [JUSDView.sol](./src/JUSDView.sol) and [JUSDMulticall.sol](./src/JUSDMulticall.sol).
- `JOJOView.sol` contains all view functions of `JUSDBank.sol`.
- `JUSDOperation.sol` contains all "onlyOwner" functions of `JUSDBank.sol`.
- `JUSDMulticall.sol` contains all "multicall" functions of `JUSDBank.sol`.
- [JUSDBankStorage.sol](./src/JUSDBankStorage.sol) is where all data stored.

## JUSD

JUSD is a stablecoin developed by the JOJO system to support multi-collateralization. JUSD works like DAI and users can mint JUSD by staking other ERC20 tokens as collateral. Then JUSD can deposit to the trading system as a position margin. The `secondaryAsset` in the trading system is referred to as JUSD.

### Loan

Users can deposit registered collateral to the lending system in the `deposit` function, and then borrow JUSD through the `borrow` function. After the trading, users can repay JUSD to the lending system by calling the `repay` function and get the collateral back in the `withdraw` function. When the value of borrowed JUSD > the value of deposited collaterals, then the trader will be liquidated. The start liquidation formula is `JUSDBorrow > sum(depositAmount * price * liquidationMortgageRate)`.

### Flashloan

Flash Loans in JOJO are special transactions that allow the withdrawal of an asset, as long as the account is safe before the end of the transaction. These transactions do not require a user to repay JUSD before engaging in the transaction.

There are two examples of lending systems: [FlashLoanRepay.sol](./src/FlashLoanRepay.sol) and [FlashLoanLiquidate](./src/FlashLoanLiquidate.sol).
`FlashLoanRepay` allows users to repay JUSD using the collateral that is deposited in the lending system.
`FlashLoanLiquidate`: The main implementation process involves selling the collateral obtained from liquidation and dividing the resulting USDC into three parts: one for repaying JUSD, another for paying insurance, and if the liquidated collateral still has a remainder, transferring it to the liquidated party in the form of USDC.

# Funding rate arbitrage

The core contract [FundingRateArbitrage](./src/FundingRateArbitrage.sol) involves offsetting trades in both the spot and perpetual markets to capture the funding rate income in perpetual trading. The liquid provider can deposit usdc to this pool and accumulate interest. 

## LP functions

LP can deposit usdc to the arbitrage pool in the `deposit` function to earn interest. If users want to withdraw the interest and capital, they can request a withdrawal. Our system will execute the request in 24 hours by calling `permitWithdrawRequests`.

## Arbitrage process

After users deposit USDC to the arbitrage pool, the admin will use the USDC to buy ETH and deposit it to the JUSDBank system (through the `swapBuyEth` function). Then admin will call `borrow` to borrow JUSD and deposit it into the trading system. At last, the admin will open short interest in the trading system to earn funding fees.

# Other questions

## Index price & Mark price

Index price and mark price are both provided by 3rd parties' price oracle. 

## Subaccount

This feature is implemented by peripheral smart contracts [subaccount](./src/subaccount/).
Subaccounts can help you separate positions and risks. You can also give trading access to others and let a professional team trade for you.

## Insurance

For each liquidation, an insurance fee is charged. When there is a bad debt, it will be covered by insurance funds. 
If the insurance account is not sufficient to cover the bad debt, the insurance fund will stay negative until it is paid off.


# Start up

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