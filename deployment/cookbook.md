# Initial Deployment Workflow

1. Deploy secondary asset. Secondary asset should have the same decimals with primary asset. Secondary asset is a simple ownable mintable ERC20 token.

2. Set up mark price source. Usually a proxy that forwards 3rd party (e.g chainlink) price source. Be aware of decimals!

3. Deploy dealer.

   2.1 Set insurance.

   2.2 Set the first order sender.

   2.3 Set funding rate keeper.

   2.4 Set withdraw timeLock

   2.5 Set max position amount

   2.6 Set secondary asset

4. Deploy Perpetual.sol with dealer as the owner in the constructor.

5. Register perpetual into dealer. Double check the risk params before set isRegistered to be true!

6. Deploy subaccount factory and funding rate update: SubaccountFactory, DegenSubaccountFactory, BotSubaccountFactory, FundingRateUpdateLimiter

7. Deploy JUSDBank, JUSDExchange and JUSDRepayHelper and set params

8. Register collateral into JUSDBank.

9. Deploy FundingRateArbitrage and init params.
