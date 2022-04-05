# smart-contract-EVM
Smart contract for JOJO Exchange (EVM version)

# What is a perpetual contract

A perpetual contract is simply a group of people who buy and sell virtual notes (also known as financial derivatives). In principle, the price of a note can be arbitrary. But through the mechanism of *funding rate*, it can be anchored to an external number, such as the "price of Bitcoin". 

In this way, trading such notes is very similar to trading bitcoin spot. Since the liquidity of such a note is independent of spot liquidity, it can achieve liquidity and leverage multiples that far exceed those of the spot market. This feature has made perpetual contracts the most popular derivative in the cryptocurrency market.

JOJO is a decentralized perpetual contract exchange based on an off-chain matching system.

# Smart contract overview
We will take you through a comprehensive understanding of the whole perpetual contract system. This is only a non-detailed introductory guide, not a specification.

There are only two core smart contracts: [Perpetual.sol](./contracts/impl/Perpetual.sol) & [JOJODealer.sol](./contracts/impl/JOJODealer.sol).

- `Perpetual.sol` is the core book of a certain perpetual contract market.
- `JOJODealer.sol` is the owner of `Perpetual.sol`. One `JOJODealer.sol` may have several `Perpetual.sol` at the same time.
- `JOJODealer.sol` is seperated into [JOJOView.sol](./contracts/impl/JOJOView.sol), [JOJOOperation.sol](./contracts/impl/JOJOOperation.sol) and [JOJOExternal.sol](./contracts/impl/JOJOExternal.sol).
- `JOJOView.sol` contains all view functions of `JOJODealer.sol`.
- `JOJOOperation.sol` contains all "onlyOwner" functions of `JOJODealer.sol`.
- `JOJOExternal.sol` contains all "external" functions of `JOJODealer.sol`.
- [JOJOStorage.sol](./contracts/impl/JOJOStorage.sol) is where all data stored.

# Perpetual.sol: The core book

From now on, we are going to design a perpetual contract computing system on the blockchain. Which refers to [Perpetual.sol](./contracts/impl/Perpetual.sol)

For a trader, we only need to maintain the number of *paper* and *credit* he holds. Both the number of *paper* and the number of *credits* can be negative. We call the combination of these two number "balance".

If a trader long 1BTC at 30,000USD, then his balance is

```javascript
paper = 1
credit = -30000
```

If a trader short 1BTC at 30,000USD, then his balance is

```javascript
paper = -1
credit = 30000
```

The essence of the perpetual contract calculation is the state transfer of balance. Luckily, there are only 3 types of operations that affect balance.

1. Funding rate
2. Trading
3. Liquidation

## Funding 

It is the responsibility of the dealer to ensure that the perpetual contract price is anchored to the spot price. The funding rate is one of the most common solutions.

- If the contract price is higher than spot, charge the long side to bring the price down
- If the contract price is lower than the spot, charge the short side to bring the price up

The funding rate adjusts *credit* according to the *paper* amount. It is impossible to record the number of credits on the chain, otherwise it would be too costly to modify thousands of credit values each time the funding rate is updated. So we record a value called "reducedCredit" on the chain, and the real credit is calculated by the following formula:

`credit = (paper * fundingRate) + reducedCredit`

In this way, each person's credit is automatically updated each time *fundingRate* is updated. *fundingRate* can be positive or negative. When *fundingRate* increases, it charges from short positions. When *fundingRate* decreases, it charges from long positions.

As for how *fundingRate* is updated, this issue is too complicated. So let's put it aside and move on to the next step.

```javascript
function balanceOf(address trader)
        external
        view
        returns (int256 paperAmount, int256 credit);
```

## Trading

Essentially this is the liquidity problem. We need to answer two questions: 
- How is liquidity supplied? 
- How is liquidity consumed? 
These two questions are more complex than the *fundingRate*, but the good news is that operationally the transaction is simple, just a few columns of modifications to *paper* and *reducedCredit*. Let's put aside the concrete calculations for now and just leave the abstract interface.

```javascript
function trade(
        bytes calldata tradeData
    ) external;
```

## Liquidation

Liquidation is a mandatory trading behavior. As we do not even define the trading, just leave liquidation aside.

```javascript
function liquidate(address liquidatedTrader, uint256 requestPaperAmount)
        external;
```

So far we have successfully defined the core Perpetual contract. Next we have to solve the outstanding issues one by one.

# JOJODealer.sol: Dealer of the table
Just as there is a dealer at the table, there is a moderator in the perpetual contract game. Dealer is the owner of the perpetual, it is responsible for solving all the problems that the perpetual does not know how to do. A dealer can have more than one perpetual at a time.

The dealer has three main responsibilities:

1. Maintaining funding rate
2. Trading
2. Liquidation

The Dealer can be designed in various ways, and JOJODealer is just one of the solutions proposed by the JOJO team.

The functions realized by JOJODealer can be summarized as
- Off-chain matching, on-chain settlement
- Corss model
- Fixed discount liquidation
- Deposit margin


## Trading: Off-chain matching, on-chain settlement
JOJODealer uses the orderbook model to provide liquidity. Orders are placed, canceled and mathced off-chain, while final settlement occurs on-chain. This architecture is similar to 0xProtocol, which allows for an excellent trading experience while keeping the system decentralized enough.

It is implemented by users signing orders and sending them to JOJO's server. Whenever orders are matched, JOJO's server submits these orders to the blockchain and immediately notifies the user on the front end.

The only centralized thing is: JOJO server need to delete order info and signature after the user cancels an order. But users may choose to sign orders with very short expiration to reduce the need for trust.

In addition, anyone can match orders, and whoever submit the matching result to blockchain receives trading fees.

See `approveTrade` in [JOJOExternal.sol](. /contracts/impl/JOJOExternal.sol).

## Cross mode
JOJODealer only offers a cross position mode, where positions under different markets share margin. Positions under either market will affect the account net value and global exposure.

See `getTraderRisk` in [JOJOView.sol](./contracts/impl/JOJOView.sol).

If you want to use the isolated mode, you can just switch wallets or create sub-accounts.

## Fixed discount liquidation
For accounts with low margin rates, JOJODealer will sell their positions at a fixed discount. Anyone can take as many positions as they want until the position is cleared or the account margin rate returns to a healthy state.

See `getLiquidationCost` in [JOJOView.sol](./contracts/impl/JOJOView.sol).

## Deposit margin

JOJODealer only accepts a single ERC20 token as margin. Deposits and with withdrawals do not require the permission of the JOJO server.

### Pending withdraw
In order to save time for the matching engine to cancel orders when users withdraw. User withdrawals need to be submitted in two steps, with a waiting period in between (no more than 1 minute).

### Virtual credit
JOJO can grant credit to some accounts to temporarily obtain more margin. This design has two main purpose:
- Supporting multi-margin feature in the future
- Matching funds to market makers in exchange for better liquidity


# Other questions
## Index price & Mark price
Index price and mark price are both provided by 3rd party's price oracle. 

## Subaccount
This feature is implemented by peripheral smart contracts [subaccount](./contracts/subaccount/).
Subaccount can help you seperate positions and risks. You can also give trading access to others and let a professional team trade for you.

## Insurance
For each liquidation, an insurance fee is charged. When there is a bad debt, it will be covered by insurance fund. 
If the insurance account is not sufficient to cover the bad debt, it will remain in a negative balance until it is paid off.