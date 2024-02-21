const { network } = require("hardhat")
const { developmentChains } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    log("----------------------------------------------------")
    const arguments = ["0x999f17A692272d4bc3c1719EbC1196A966A9Cb23"]
    const BadgerBotStakingContract = await deploy("BadgerBotStakingContract", {
        from: deployer,
        args: arguments,
        log: true,
        waitConfirmations: network.config.blockConfirmations || 1,
    })

    // Verify the deployment
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        log("Verifying...")
        await verify(BadgerBotStakingContract.address, arguments)
    }
}

module.exports.tags = ["all", "BadgerBotStakingContract", "main"]
