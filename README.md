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
- `JOJODealer.sol` is seperated into [JOJOView.sol](./contracts/impl/JOJOView.sol) [JOJOOperation.sol](./contracts/impl/JOJOOperation.sol) and [JOJOExternal.sol](./contracts/impl/JOJOExternal.sol).
- `JOJOView.sol` contains all view functions of `JOJODealer.sol`.
- `JOJOOperation.sol` contains all "onlyOwner" functions of `JOJODealer.sol`.
- `JOJOExternal.sol` contains all "external" functions of `JOJODealer.sol`.
- `JOJOStorage.sol` is where all data stored.

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