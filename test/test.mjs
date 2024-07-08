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

    beforeEach(async function () {
        [owner, addr1, addr2, bot, weth] = await ethers.getSigners();
        
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
    
            // Convert BigNumber to a regular number for comparison
            const totalSupply = await badgerBotPool.totalSupply();
            expect(totalSupply.toNumber()).to.equal(1);
    
            // Convert BigNumber to a regular number for comparison
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

            // Convert BigNumber to a regular number for comparison
            const totalSupply = await badgerBotPool.totalSupply();
            expect(totalSupply.toNumber()).to.equal(6);
    
            // Convert BigNumber to a regular number for comparison
            const ownerOfToken = await badgerBotPool.ownerOf(6);
            expect(ownerOfToken).to.equal(addr1.address);
        });
    });
});
