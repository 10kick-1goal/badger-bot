import { expect, use } from 'chai';
import chaiAsPromised from 'chai-as-promised';
import hardhat from "hardhat";
import { waffleChai } from '@ethereum-waffle/chai';

use(chaiAsPromised);
use(waffleChai);

const { ethers } = hardhat;

describe("BadgerBotStakingContract", function () {
  let BadgerBotStakingContract, stakingContract;
  let poolContract;
  let DateTime, dateTimeContract;
  let WETH, weth;
  let owner, bot, addr1, addr2, addr3, team;
  
  const existingNFTCollectionAddress = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"; // Replace with actual address
  
  beforeEach(async function () {
    [owner, bot, addr1, addr2, addr3, team] = await ethers.getSigners();

    // Deploy WETH mock contract
    const WETHFactory = await ethers.getContractFactory("MockWETH");
    weth = await WETHFactory.deploy();
    await weth.deployed();

    // Deploy DateTime library
    // const DateTimeFactory = await ethers.getContractFactory("DateTime");
    // dateTimeContract = await DateTimeFactory.deploy();
    // await dateTimeContract.deployed();

    // Deploy poolContract contract
    const poolContractFactory = await ethers.getContractFactory("BadgerBotPool");
    poolContract = await poolContractFactory.deploy(bot.address, weth.address, "https://example.com/metadata/");
    await poolContract.deployed();

    // Deploy BadgerBotStakingContract with references to other contracts
    const BadgerBotStakingContractFactory = await ethers.getContractFactory("BadgerBotStakingContract" 
    // {
    //   libraries: {
    //     DateTime: dateTimeContract.address,
    //   },
    //  }
    );
    stakingContract = await BadgerBotStakingContractFactory.deploy(poolContract.address, team.address);
    await stakingContract.deployed();
    await poolContract.connect(owner).setStakingContractAddress(stakingContract.address);
    expect(await poolContract.stakingContract()).to.equal(stakingContract.address);
  });

  describe("Staking NFT and Funds", function () {
    it("Staking and Unstaking an NFT", async function () {
      // // Listen for Debug events
      // stakingContract.on('Debug', (message, value) => {
      //   console.log(`Debug event: ${message} - ${value.toString()}`);
      // });
        
      // Mint an NFT to addr1
      await poolContract.editMintWindows(true);
      await poolContract.connect(addr1).safeMint(addr1.address, { value: ethers.utils.parseEther("0") });
      await poolContract.connect(addr2).safeMint(addr2.address, { value: ethers.utils.parseEther("0") });
      
      // Check the owner of the token
      expect(await poolContract.ownerOf(1)).to.equal(addr1.address);
      expect(await poolContract.ownerOf(2)).to.equal(addr2.address);

      // Stake NFT by addr1

      console.log("---------  Staking  --------------------");
      let totalStakedSupply;
      await poolContract.connect(addr1).approve(stakingContract.address, 1);

      await expect(stakingContract.connect(addr1).stake(1))
        .to.emit(stakingContract, 'Staked')
        .withArgs(addr1.address, 1);

      let stakedAsset1 = await stakingContract.getUserStakeInfo(addr1.address);
      expect(stakedAsset1.tokenId).to.equal(1);
      expect(stakedAsset1.staked).to.equal(true);

      // Stake NFT by addr2
      await poolContract.connect(addr2).approve(stakingContract.address, 2);

      await expect(stakingContract.connect(addr2).stake(2))
      .to.emit(stakingContract, 'Staked')
      .withArgs(addr2.address, 2);

      totalStakedSupply = await stakingContract.totalStakedSupply();
      expect(totalStakedSupply).to.equal(2);

      const users = await stakingContract.getUsers();
      // console.log("users:", users);

      let userFunds1;
      let userFunds2;

      // Unstake NFT
      // await expect(stakingContract.connect(addr1).unstake(1))
      // .to.emit(stakingContract, 'Unstaked')
      // .withArgs(addr1.address, 1);

      // // Verify the staked asset details
      // stakedAsset1 = await stakingContract.getUserStakeInfo(addr1.address);
      // console.log("stakedAsset1:", stakedAsset1);
      // expect(stakedAsset1.tokenId).to.equal(0);
      // expect(stakedAsset1.staked).to.equal(false);

      // Deposit into staking contract by addr1

      let poolBalance = await stakingContract.getTotalFunds();
      let poolAllocation = await stakingContract.allocationTotal();
      let ratio = await stakingContract.getRatio();
      // console.log("poolBalance:", ethers.utils.formatEther(poolBalance), "ETH");
      // console.log("poolAllocation:", ethers.utils.formatEther(poolAllocation));
      // console.log("poolRatio:", ethers.utils.formatEther(ratio));

      console.log("---------  First Deposit  --------------------");
      const depositAmount1 = ethers.utils.parseEther("2.0");
      await expect(stakingContract.connect(addr1).deposit({ value: depositAmount1 }))
        .to.emit(stakingContract, 'Deposit')
        .withArgs(addr1.address, depositAmount1);

      // Verify the deposit was recorded
      stakedAsset1 = await stakingContract.getUserStakeInfo(addr1.address);
      expect(stakedAsset1.deposited).to.equal(true);
      let depositAmountThisMonth = await stakingContract.depositAmountThisMonth();
      expect(depositAmountThisMonth).to.equal(depositAmount1);

      poolBalance = await stakingContract.getTotalFunds();
      expect(poolBalance).to.equal(depositAmount1);

      // Bot buys a flip NFT

      console.log("---------  First Flip  --------------------");
      const collectionAddress = existingNFTCollectionAddress;
      const tokenId1 = 1;
      let price = ethers.utils.parseEther("1.0");
      const metadata = "metadata";

      let profit = ethers.utils.parseEther("0.4");
      let sellPrice = price.add(profit);
      
      let reverted = false;
      try {
          await poolContract.connect(addr1).buyFlipNFT(collectionAddress, tokenId1, price, metadata);
      } catch (error) {
          reverted = true;
          expect(error.message).to.include("Not the Bot");
      }
      expect(reverted).to.be.true;

      await poolContract.connect(bot).buyFlipNFT(collectionAddress, tokenId1, price, metadata);

      const flipNFT1 = await poolContract.getFlipNFT(collectionAddress, tokenId1);
      expect(flipNFT1.collectionAddress).to.equal(collectionAddress);
      expect(flipNFT1.tokenId).to.equal(tokenId1);
      expect(flipNFT1.price).to.equal(price);
      expect(flipNFT1.metadata).to.equal(metadata);

      // Bot sells a flip NFT

      reverted = false;
      try {
          await poolContract.connect(addr1).sellFlipNFT(collectionAddress, tokenId1);
      } catch (error) {
          reverted = true;
          expect(error.message).to.include("Not the Bot");
      }
      expect(reverted).to.be.true;

      await poolContract.connect(bot).sellFlipNFT(collectionAddress, tokenId1, { value: sellPrice });
      
      // Deposit into staking contract by addr2

      console.log("---------  Second Deposit  --------------------");
      const depositAmount2 = ethers.utils.parseEther("2.0");
      await expect(stakingContract.connect(addr2).deposit({ value: depositAmount2 }))
        .to.emit(stakingContract, 'Deposit')
        .withArgs(addr2.address, depositAmount2);

      // Verify the deposit was recorded
      let stakedAsset2 = await stakingContract.getUserStakeInfo(addr2.address);
      expect(stakedAsset2.deposited).to.equal(true);

      depositAmountThisMonth = await stakingContract.depositAmountThisMonth();
      expect(depositAmountThisMonth).to.equal(depositAmount1.add(depositAmount2));

      // poolBalance = await stakingContract.getTotalFunds();
      // poolAllocation = await stakingContract.allocationTotal();
      // ratio = await stakingContract.getRatio();
      // console.log("poolBalance after 2nd deposit:", ethers.utils.formatEther(poolBalance), "ETH");
      // console.log("poolAllocation after 2nd deposit:", ethers.utils.formatEther(poolAllocation));
      // console.log("poolRatio after 2nd deposit:", ethers.utils.formatEther(ratio));

      // userFunds1 = await stakingContract.getUserFunds(addr1.address);
      // userFunds2 = await stakingContract.getUserFunds(addr2.address);
      // console.log("1st userFunds before withdraw:", ethers.utils.formatEther(userFunds1), "ETH");
      // console.log("2nd userFunds before withdraw:", ethers.utils.formatEther(userFunds2), "ETH");

      // Bot buys a flip NFT

      console.log("---------  Second Flip  --------------------");
      const tokenId2 = 1;
      price = ethers.utils.parseEther("2.0");

      profit = ethers.utils.parseEther("0.6");
      sellPrice = price.add(profit);
      
      await poolContract.connect(bot).buyFlipNFT(collectionAddress, tokenId2, price, metadata);

      const flipNFT = await poolContract.getFlipNFT(collectionAddress, tokenId2);

      // Bot sells a flip NFT

      await poolContract.connect(bot).sellFlipNFT(collectionAddress, tokenId2, { value: sellPrice });

      let allFlipNFTs = await poolContract.getAllFlipNFTs();
      let totalAssetsValue = await poolContract.getTotalAssetsValue();
      // console.log("allFlipNFTs:", allFlipNFTs.toString());
      // console.log("totalAssetsValue:", ethers.utils.formatEther(totalAssetsValue), "ETH");

      // poolBalance = await stakingContract.getTotalFunds();
      // poolAllocation = await stakingContract.allocationTotal();
      // ratio = await stakingContract.getRatio();
      // console.log("poolBalance after flipping:", ethers.utils.formatEther(poolBalance), "ETH");
      // console.log("poolAllocation after flipping:", ethers.utils.formatEther(poolAllocation));
      // console.log("poolRatio after flipping:", ethers.utils.formatEther(ratio));
      
      // userFunds1 = await stakingContract.getUserFunds(addr1.address);
      // userFunds2 = await stakingContract.getUserFunds(addr2.address);
      // console.log("1st userFunds after flipping:", ethers.utils.formatEther(userFunds1), "ETH");
      // console.log("2nd userFunds after flipping:", ethers.utils.formatEther(userFunds2), "ETH");

      //Request wrong withdraw profit

      reverted = false;
      try {
          await stakingContract.connect(addr1).requestWithdrawProfit();
      } catch (error) {
          reverted = true;
          expect(error.message).to.include("You can request withdraw profit since next month.");
      }
      expect(reverted).to.be.true;

      reverted = false;
      try {
          await stakingContract.connect(addr3).requestWithdrawProfit();
      } catch (error) {
          reverted = true;
          expect(error.message).to.include("User has no staked asset.");
      }
      expect(reverted).to.be.true;

      //Reward distribution

      console.log("---------  Reward Distribution  --------------------");
      let tx = await stakingContract.connect(owner).rewardDistribution();
      let receipt = await tx.wait();

      let block = await ethers.provider.getBlock(receipt.blockNumber);
      let currentTimestamp = block.timestamp;
      
      await expect(tx)
        .to.emit(stakingContract, 'RewardsDistributed')
        .withArgs(currentTimestamp);

      poolBalance = await stakingContract.getTotalFunds();
      poolAllocation = await stakingContract.allocationTotal();
      ratio = await stakingContract.getRatio();
      console.log("poolBalance after distribution:", ethers.utils.formatEther(poolBalance), "ETH");
      console.log("poolAllocation after distribution:", ethers.utils.formatEther(poolAllocation));
      console.log("poolRatio after distribution:", ethers.utils.formatEther(ratio));

      userFunds1 = await stakingContract.getUserFunds(addr1.address);
      userFunds2 = await stakingContract.getUserFunds(addr2.address);
      console.log("1st userFunds after distribution:", ethers.utils.formatEther(userFunds1), "ETH");
      console.log("2nd userFunds after distribution:", ethers.utils.formatEther(userFunds2), "ETH");

      // Request a withdrawal

      const withdrawPercent = 25;
      const expectedWithdrawAmount = userFunds1.mul(withdrawPercent).div(100);

      tx = await stakingContract.connect(addr1).requestWithdraw(withdrawPercent);
      receipt = await tx.wait();

      block = await ethers.provider.getBlock(receipt.blockNumber);
      currentTimestamp = block.timestamp;      
      await expect(tx)
        .to.emit(stakingContract, 'WithdrawUserFunds')
        .withArgs(addr1.address, expectedWithdrawAmount, currentTimestamp);

      // Verify the withdrawal
      userFunds1 = await stakingContract.getUserFunds(addr1.address);
      console.log("1st userFunds after withdraw:", ethers.utils.formatEther(userFunds1), "ETH");
      stakedAsset1 = await stakingContract.getUserStakeInfo(addr1.address);
      console.log("1st user's allocation after withdraw:",ethers.utils.formatEther(stakedAsset1.allocation));
            
      // // Remove event listener
      // stakingContract.off('Debug');
    });
  });
});
