const { abi } = require('../../out/JOJODealer.sol/JOJODealer.json');
const { Web3 } = require('web3');
require('dotenv').config();

function requireArg(arg, argName) {
    if (!arg[argName] && arg[argName] != false) {
        console.log(argName + " required");
        throw "arg required";
    }
}
function getDealerContract(web3, dealerAddress) {
    return dealer = new web3.eth.Contract(abi, dealerAddress)
}

function getNodeUrl(network) {
    switch (network) {
        case "goerli":
            return process.env["GOERLI_URL"];
            break;
        case "bsctest":
            return process.env["BSCTEST_URL"];
            break;
        case "bsc":
            return process.env["BSC_URL"];
        case "arbitrum":
            return process.env["ARBITRUM_URL"];
    }
}

async function viewDealer(network, dealerAddress) {
    var web3 = new Web3(getNodeUrl(network));
    var dealer = getDealerContract(web3, dealerAddress);
    let state = await dealer.methods.state().call();
    console.log(`primaryAsset:${state.primaryAsset}`);
    console.log(`secondaryAsset:${state.secondaryAsset}`);
    console.log(`insurance:${state.insurance}`);
    console.log(`fundingRateKeeper:${state.fundingRateKeeper}`);
    console.log(`withdrawTimeLock:${state.withdrawTimeLock}`);
    let dealerOwner = await dealer.methods.owner().call();
    console.log(`dealer owner: ${dealerOwner}`);
    let perps = await dealer.methods.getAllRegisteredPerps().call();
    console.log(`${perps.length} Perps registered:\n${perps}`);
    for (let i = 0; i < perps.length; i++) {
        let perp = perps[i];
        console.log(`==============================`);
        console.log(`Details of ${perp}\n`);
        let price = await dealer.methods.getMarkPrice(perp).call();
        console.log(`price:${price.toString()}\n`);
        let params = await dealer.methods.getRiskParams(perp).call();
        let iniitialRate = parseFloat(params[0]) / parseFloat(1e18);
        console.log(`iniitialRate:${iniitialRate}\n`);
        let liquidationThreshold = parseFloat(params[1]) / parseFloat(1e18);
        console.log(`liquidationThreshold:${liquidationThreshold}\n`);

        let liquidationPriceOff = parseFloat(params[2]) / parseFloat(1e18);
        console.log(`liquidationPriceOff:${liquidationPriceOff}\n`);

        let insuranceFeeRate = parseFloat(params[3]) / parseFloat(1e18);
        console.log(`insuranceFeeRate:${insuranceFeeRate}\n`);
        console.log(`markPriceSource:${params[4]}\n`);
        console.log(`name:${params[5]}\n`);
        console.log(`isRegistered:${params[6]}\n`);
    }
}

var argv = require("minimist")(process.argv.slice(2), {
    string: ["dealer", "deployer"],
});

requireArg(argv, "network");
requireArg(argv, "dealer");
viewDealer(argv["network"], argv["dealer"]);