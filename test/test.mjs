import { expect } from "chai";
import hardhat from "hardhat";

const { ethers } = hardhat;

describe("BadgerBotPool", function () {
    let BadgerBotPool;
    let badgerBotPool;
    let owner;
    let addr1;
    let addr2;
    let bot;
    let weth;
    let stakingContract;
    const existingNFTCollectionAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"; // Replace with actual address

    beforeEach(async function () {
        [owner, addr1, addr2, bot, stakingContract, weth] = await ethers.getSigners();

        // Deploy a mock WETH contract
        const WETH = await ethers.getContractFactory("MockWETH");
        weth = await WETH.deploy();
        await weth.deployed();

        // Deploy the BadgerBotPool contract
        BadgerBotPool = await ethers.getContractFactory("BadgerBotPool");
        badgerBotPool = await BadgerBotPool.deploy(bot.address, weth.address, "https://example.com/metadata/");
        await badgerBotPool.deployed();
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await badgerBotPool.owner()).to.equal(owner.address);
        });

        it("Should have the correct initial baseURI", async function () {
            expect(await badgerBotPool.getBaseURI()).to.equal("https://example.com/metadata/");
        });
    });

    describe("Minting", function () {
        it("Should not allow minting if public mint is closed", async function () {
            let reverted = false;
            try {
                await badgerBotPool.connect(addr1).safeMint(addr1.address, { value: ethers.utils.parseEther("0") });
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Public Mint Closed");
            }
            expect(reverted).to.be.true;
        });

        it("Should mint a new token to an address", async function () {
            await badgerBotPool.connect(owner).editMintWindows(true);
            await badgerBotPool.connect(addr1).safeMint(addr1.address, { value: ethers.utils.parseEther("0") });

            const totalSupply = await badgerBotPool.totalSupply();
            expect(totalSupply.toNumber()).to.equal(1);

            const ownerOfToken = await badgerBotPool.ownerOf(1);
            expect(ownerOfToken).to.equal(addr1.address);
        });

        it("Should respect max mint per wallet limit", async function () {
            await badgerBotPool.connect(owner).editMintWindows(true);
            await badgerBotPool.connect(owner).editMaxMintPerWallet(1);

            await badgerBotPool.connect(addr1).safeMint(addr1.address, { value: ethers.utils.parseEther("0") });
            let reverted = false;
            try {
                await badgerBotPool.connect(addr1).safeMint(addr1.address, { value: ethers.utils.parseEther("0") });
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Max Mint per wallet reached");
            }
            expect(reverted).to.be.true;
        });
    });

    describe("Whitelist", function () {
        it("Should allow owner to add and remove addresses from whitelist", async function () {
            await badgerBotPool.connect(owner).addToWhitelist(addr1.address);
            expect(await badgerBotPool.whitelist(addr1.address)).to.be.true;

            await badgerBotPool.connect(owner).removeFromWhitelist(addr1.address);
            expect(await badgerBotPool.whitelist(addr1.address)).to.be.false;
        });

        it("Should airdrop NFTs to whitelisted addresses", async function () {
            await badgerBotPool.connect(owner).addToWhitelist(addr1.address);
            await badgerBotPool.connect(owner).airdropNFT();

            const totalSupply = await badgerBotPool.totalSupply();
            expect(totalSupply.toNumber()).to.equal(6);

            const ownerOfToken = await badgerBotPool.ownerOf(6);
            expect(ownerOfToken).to.equal(addr1.address);
        });
    });

    describe("NFT Flipping", function () {
        it("Should allow the bot to buy and sell flip NFTs", async function () {
            // Bot buys a flip NFT
            const collectionAddress = existingNFTCollectionAddress;
            const tokenId = 1;
            const price = ethers.utils.parseEther("1");
            const metadata = "metadata";

            await badgerBotPool.connect(bot).buyFlipNFT(collectionAddress, tokenId, price, metadata);

            const flipNFT = await badgerBotPool.getFlipNFT(collectionAddress, tokenId);
            expect(flipNFT.collectionAddress).to.equal(collectionAddress);
            expect(flipNFT.tokenId).to.equal(tokenId);
            expect(flipNFT.price).to.equal(price);
            expect(flipNFT.metadata).to.equal(metadata);

            // Bot sells a flip NFT
            await badgerBotPool.connect(bot).sellFlipNFT(collectionAddress, tokenId, { value: price });

            const flipNFTExists = await badgerBotPool.isFlipNFTExisted(collectionAddress, tokenId);
            expect(flipNFTExists).to.be.false;
        });

        it("Should not allow non-bot to buy and sell flip NFTs", async function () {
            const collectionAddress = existingNFTCollectionAddress;
            const tokenId = 1;
            const price = ethers.utils.parseEther("1");
            const metadata = "metadata";

            let reverted = false;
            try {
                await badgerBotPool.connect(addr1).buyFlipNFT(collectionAddress, tokenId, price, metadata);
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Not the Bot");
            }
            expect(reverted).to.be.true;

            reverted = false;
            try {
                await badgerBotPool.connect(addr1).sellFlipNFT(collectionAddress, tokenId);
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Not the Bot");
            }
            expect(reverted).to.be.true;
        });
    });

    describe("Interactions with Staking Contract", function () {
        it("Should allow the staking contract to withdraw ETH", async function () {
            const amount = ethers.utils.parseEther("1");

            // Send some ETH to the contract
            await owner.sendTransaction({ to: badgerBotPool.address, value: amount });

            // Staking contract withdraws ETH
            await badgerBotPool.connect(owner).setStakingContractAddress(stakingContract.address);
            await badgerBotPool.connect(stakingContract).withdrawByStakingContract(addr1.address, amount);

            const balance = await ethers.provider.getBalance(addr1.address);
            expect(balance).to.equal(amount);
        });

        it("Should not allow non-staking contract to withdraw ETH", async function () {
            const amount = ethers.utils.parseEther("1");

            // Send some ETH to the contract
            await owner.sendTransaction({ to: badgerBotPool.address, value: amount });

            let reverted = false;
            try {
                await badgerBotPool.connect(addr1).withdrawByStakingContract(addr1.address, amount);
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Not the Staking Contract");
            }
            expect(reverted).to.be.true;
        });
    });

    describe("WETH related functions", function () {
        it("Should allow the staking contract to swap ETH to WETH and WETH to ETH", async function () {
            const amount = ethers.utils.parseEther("1");

            // Send some ETH to the contract
            await owner.sendTransaction({ to: badgerBotPool.address, value: amount });

            // Swap ETH to WETH
            await badgerBotPool.connect(owner).setStakingContractAddress(stakingContract.address);
            await badgerBotPool.connect(stakingContract).swapEthToWeth(amount);

            let wethBalance = await weth.balanceOf(badgerBotPool.address);
            expect(wethBalance).to.equal(amount);

            // Swap WETH to ETH
            await badgerBotPool.connect(stakingContract).swapWethToEth(amount);

            wethBalance = await weth.balanceOf(badgerBotPool.address);
            expect(wethBalance).to.equal(0);
        });

        it("Should not allow non-staking contract to swap ETH to WETH and WETH to ETH", async function () {
            const amount = ethers.utils.parseEther("1");

            // Send some ETH to the contract
            await owner.sendTransaction({ to: badgerBotPool.address, value: amount });

            let reverted = false;
            try {
                await badgerBotPool.connect(addr1).swapEthToWeth(amount);
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Not the Staking Contract");
            }
            expect(reverted).to.be.true;

            // Swap ETH to WETH through staking contract
            await badgerBotPool.connect(owner).setStakingContractAddress(stakingContract.address);
            await badgerBotPool.connect(stakingContract).swapEthToWeth(amount);

            reverted = false;
            try {
                await badgerBotPool.connect(addr1).swapWethToEth(amount);
            } catch (error) {
                reverted = true;
                expect(error.message).to.include("Not the Staking Contract");
            }
            expect(reverted).to.be.true;
        });
    });
});
