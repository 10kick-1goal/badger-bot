const { ethers, network } = require("hardhat")
const { verify } = require("../utils/verify")

async function main() {
    console.log("----------------------------------------------------")
    const nftCollectionAddress = "0xc1BFc3350564A70888d23Ca883EcAFdd107815c7";
    const wethAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"; 

    const Contract = await ethers.getContractFactory('BadgerBotStakingContract');
    const contract = await Contract.deploy(nftCollectionAddress, wethAddress);

    console.log("Contract address: ", contract.address);

    await contract.deployed()

    // Verify the deployment
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     log("Verifying...")
    //     await verify(BadgerBotStakingContract.address, arguments)
    // }
}

main()
.catch((error) => {
    console.error(error)
    process.exitCode = 1
})
