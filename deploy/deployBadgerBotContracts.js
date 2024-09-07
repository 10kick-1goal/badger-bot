const { ethers, network } = require("hardhat")
const { verify } = require("../utils/verify")

async function main() {
    console.log("----------------------------------------------------")
    console.log("Deploying BadgerBotPool and BadgerBotStakingContract to Sepolia")
    console.log("----------------------------------------------------")

    // Deploy BadgerBotPool first
    const botAddress = "0x840F795E46277DdC58eB6c3ad8deCE2221FAdF4E"
    const wethSepoliaAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    const initBaseURI = process.env.TEST_BASE_URI

    const BadgerBotPool = await ethers.getContractFactory("BadgerBotPool")
    const badgerBotPool = await BadgerBotPool.deploy(botAddress, wethSepoliaAddress, initBaseURI)
    await badgerBotPool.deployed()

    console.log("BadgerBotPool deployed to:", badgerBotPool.address)

    // Deploy BadgerBotStakingContract
    const teamAddress = "0x6360A1E7dFe205397d7EF463cb28f16Fbdaa2D24"

    const BadgerBotStakingContract = await ethers.getContractFactory("BadgerBotStakingContract")
    const badgerBotStakingContract = await BadgerBotStakingContract.deploy(
        badgerBotPool.address,
        teamAddress,
    )
    await badgerBotStakingContract.deployed()

    console.log("BadgerBotStakingContract deployed to:", badgerBotStakingContract.address)

    // Set the staking contract address in BadgerBotPool
    await badgerBotPool.setStakingContractAddress(badgerBotStakingContract.address)
    console.log("Staking contract address set in BadgerBotPool")

    console.log("----------------------------------------------------")
    console.log("Deployment completed")
    console.log("----------------------------------------------------")

    // Verify contracts on Etherscan
    if (network.name === "sepolia") {
        console.log("Verifying contracts on Etherscan...")
        await verify(badgerBotPool.address, [botAddress, wethSepoliaAddress, initBaseURI])
        await verify(badgerBotStakingContract.address, [badgerBotPool.address, teamAddress])
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
