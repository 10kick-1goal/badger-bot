// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BadgerBotStakingContract.sol";
import "./BadgerBotPool.sol";
import "./DateTime.sol";

/// @author Hiroki Hara
/// @title BadgerBot Reward Distribution Contract
/// @dev This contract handles the monthly reward distribution for users.

contract BadgerBotRewardDistributionContract is ReentrancyGuard {
    BadgerBotStakingContract public stakingContract;
    BadgerBotPool public nftCollection;

    address public owner;
    uint256 public lastDistributionTimestamp;
    uint256 team = 20;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    event RewardsDistributed(uint256 timestamp);

    constructor(address _stakingContract, address _nftCollection) {
        owner = msg.sender;
        stakingContract = BadgerBotStakingContract(_stakingContract);
        nftCollection = BadgerBotPool(_nftCollection);
        lastDistributionTimestamp = 0;
    }

    function distributeRewards() external onlyOwner nonReentrant {
        require(isFirstOfMonth(), "Today is not the 1st of the month");
        require(block.timestamp > lastDistributionTimestamp + 30 days, "Already distributed this month");

        uint256 walletTotalOld = getPoolWalletTotalOld();
        uint256 walletTotalCurrent = getPoolWalletOldCurrent();
        uint256 profitInv = (walletTotalCurrent - walletTotalOld) * (100 - team) / 100;
        uint256 profitTeam = (walletTotalCurrent - walletTotalOld) * team / 100;

        stakingContract.depositToPool();

        lastDistributionTimestamp = block.timestamp;

        emit RewardsDistributed(block.timestamp);
    }

    function getPoolWalletTotalOld() internal view onlyOwner returns (uint256) {
        uint256 walletBalanceOld = nftCollection.getWalletTotalOld();
        return walletBalanceOld;
    }

    function getPoolWalletOldCurrent() internal view onlyOwner returns (uint256) {
        uint256 walletBallanceCurrent = nftCollection.calculateWalletTotalCurrent();
        return walletBallanceCurrent;
    }

    function isFirstOfMonth() internal view returns (bool) {
        uint256 currentTime = block.timestamp;
       (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(currentTime);
        return day == 1;
    }
}
