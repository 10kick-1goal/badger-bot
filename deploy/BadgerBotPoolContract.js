const { ethers, network } = require("hardhat")
const { verify } = require("../utils/verify")

async function main() {
    console.log("----------------------------------------------------")
    const botAddress = "0x840F795E46277DdC58eB6c3ad8deCE2221FAdF4E";
    const wethSepoliaAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14";
    const wethEthereumAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    const initBaseURI = process.env.TEST_BASE_URI;

    const Contract = await ethers.getContractFactory('BadgerBotPool');
    const contract = await Contract.deploy(botAddress, wethSepoliaAddress, initBaseURI);

    console.log("Contract address: ", contract.address);

    await contract.deployed()
}

main()
.catch((error) => {
    console.error(error)
    process.exitCode = 1
})