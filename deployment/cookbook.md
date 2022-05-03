# Initial Deployment Workflow
1. Deploy secondary asset. Secondary asset should have the same decimals with primary asset. Secondary asset is a simple ownable mintable ERC20 token. 

    1.1 After deployed, transfer ownership from deployer to multisig wallet.

2. Deploy dealer. 

    2.1 First deploy and verify 3 libraries.

    2.2 Link libraries to dealer contract and deploy.

    2.3 Set insurance.

    2.4 Set the first order sender.

    2.5 Set funding rate keeper.

    2.6 Set withdraw timeLock

    2.7 Transfer ownership from deployer to multisig wallet.

3. If needed, set secondary asset.

# Add Perpetual

1. Set up mark price source. Usually a proxy that forwards 3rd party (e.g chainlink) price source. Be aware of decimals!

2. Deploy Perpetual.sol with dealer as the owner in the constructor.

3. Register perpetual into dealer. Double check the risk params before set isRegistered to be true!

# Update Funding Rate

The funding rate is calculated offchain. Be aware of the folloing possible misoperations:
1. Update funding rate to a significantly unreasonable number.
2. Transaction stucked.
3. Repeated update funding rate.