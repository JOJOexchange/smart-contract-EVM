const { abi } = require('../../out/JWrapMUSDC.sol/JWrapMUSDC.json');
const { Web3 } = require('web3');

async function callContractMethod() {

    var web3 = new Web3("https://mainnet.base.org");
    const contractAddress = '0x28f2dac5b993caab0fe3e7a777fc40d0c920d78c';

    const jwrapMUSDC = new web3.eth.Contract(abi, contractAddress);
    try {
        // 15988665
        // 15779220
        const value = await jwrapMUSDC.methods.getIndex().call({}, 15988393);
        console.log(`合约返回的值: ${value}`);
    } catch (error) {
        console.error(`调用合约方法时出错: ${error}`);
    }
}

callContractMethod();
