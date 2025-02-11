const { ethers, network } = require("hardhat")
const { verify } = require("../utils/verify")

async function main() {
    console.log("----------------------------------------------------")
    const nftCollectionAddress = "0x6391A65821dd53E6557946d7e4514205e1bcBE01";
    const teamAddress = "0x6360A1E7dFe205397d7EF463cb28f16Fbdaa2D24";

    const Contract = await ethers.getContractFactory('BadgerBotStakingContract');
    const contract = await Contract.deploy(nftCollectionAddress, teamAddress);

    console.log("Contract address: ", contract.address);

    await contract.deployed()
}

main()
.catch((error) => {
    console.error(error)
    process.exitCode = 1
})
