// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";


/// @author Shola Ayeni
/// @title BadgerBot NFT Staking Contract
/// @notice Staking Contract that uses the Openzepellin Staking model to distribute ERC20 token rewards in a dynamic way,
/// proportionally based on the amount of ERC721 tokens staked by each staker at any given time.

contract BadgerBotStakingContract is ERC721Holder, ReentrancyGuard, ChainlinkClient, ConfirmedOwner {

    using Chainlink for Chainlink.Request;
    uint256 public profit;
    bytes32 private jobId;
    uint256 private fee;

    IERC721 public nftCollection;

    uint256 public nextDistributionDate;
    uint256 public lastUpdateTime;
    uint256 public totalStakedSupply;
    address[] private users;
    bool private profitDistributed = false;
    uint public totalSupply = 5;

    mapping(address => uint256) private rewards;
    mapping(uint256 => address) public stakedAssets;
    mapping(address => uint256[]) private tokensStaked;
    mapping(uint256 => uint256) public tokenIdToIndex;

    constructor(address _nftCollection) payable ConfirmedOwner(msg.sender){
        nftCollection = IERC721(_nftCollection);
        setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = (1 * LINK_DIVISIBILITY) / 10;
    }

    function userExist(address _address) internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function removeUser(address _user) internal {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _user) {
                users[i] = users[users.length - 1];
                users.pop();
            }
        }
    }


    function stake(uint256[] memory tokenIds) external {
        require(tokenIds.length != 0, "Staking: No tokenIds provided");

        uint256 amount = tokenIds.length;
        for (uint256 i = 0; i < amount; i += 1) {
            nftCollection.safeTransferFrom(msg.sender, address(this), tokenIds[i]);

            stakedAssets[tokenIds[i]] = msg.sender;
            tokensStaked[msg.sender].push(tokenIds[i]);
            tokenIdToIndex[tokenIds[i]] = tokensStaked[msg.sender].length - 1;
        }
        totalStakedSupply += amount;

         if (!userExist(msg.sender)) {
            users.push(msg.sender);
        }
        emit Staked(msg.sender, tokenIds);
    }

    function unstake(uint256[] memory tokenIds) public nonReentrant {
        require(tokenIds.length != 0, "Staking: No tokenIds provided");

        uint256 amount = tokenIds.length;
        uint256[] storage userTokens = tokensStaked[msg.sender];

        for (uint256 i = 0; i < amount; i += 1) {
            require(stakedAssets[tokenIds[i]] == msg.sender, "Staking: Not the staker of the token");

            nftCollection.safeTransferFrom(address(this), msg.sender, tokenIds[i]);

            stakedAssets[tokenIds[i]] = address(0);


            uint256 index = tokenIdToIndex[tokenIds[i]];
            uint256 lastTokenIdIndex = userTokens.length - 1;
            if (index != lastTokenIdIndex) {
                uint256 lastTokenId = userTokens[lastTokenIdIndex];
                userTokens[index] = lastTokenId;
                tokenIdToIndex[lastTokenId] = index;
            }
            userTokens.pop();
        }
        totalStakedSupply -= amount;

        if (userTokens.length < 1) {
            removeUser(msg.sender);
        }
        claimRewards(msg.sender);
        emit Unstaked(msg.sender, tokenIds);
    }


	function requestProfitData() public onlyOwner returns (bytes32 requestId) {
        Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        req.add("get","https://badger-backend-952bd65fee6e.herokuapp.com/profit?period=7");
		req.add("path", "netProfit"); 

        int256 timesAmount = 10 ** 18;
        req.addInt("times", timesAmount);

        return sendChainlinkRequest(req, fee);
    }

     function fulfill(bytes32 _requestId, uint256 _profit) public recordChainlinkFulfillment(_requestId) {
        emit RequestProfit(_requestId, _profit);
        profit = _profit;
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function claimRewards(address _to) public nonReentrant updateReward(msg.sender) {
        address to = payable(_to);
        // move to get available rewards
        uint256 reward = getAvailableRewards(_to);
        if (reward > 0) {
            (bool success,) = to.call{value: reward}("");
            require(success, "Failed to send Ether");
            emit RewardPaid(msg.sender, reward);
        }
    }

    function unstakeAll() external {
        claimRewards(msg.sender);
        unstake(tokensStaked[msg.sender]);
    }

    function userStakeInfo(address _user)
        public
        view
        returns (uint256[] memory _tokensStaked, uint256 _availableRewards)
    {
        _tokensStaked = tokensStaked[_user];
        _availableRewards = getAvailableRewards(_user);
    }


    function lastTimeRewardApplicable() public view returns (uint256 _lastRewardsApplicable) {
        return block.timestamp;
    }


    function calculateRewards(address _user) public view returns (uint256 _rewards) {
        uint256 amount = tokensStaked[_user].length;
        return amount * profit * 3 / (totalSupply * 10);
    }


    function getAvailableRewards(address _user) public view returns (uint256 _rewards) {
        return rewards[_user];
    }

    function distributeRewards() public onlyOwner {
        require(lastUpdateTime == 0 || block.timestamp >= lastUpdateTime + 7 days, "Not enough time has passed");
        requestProfitData();
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userReward = rewards[users[i]];
            uint256 currentReward = calculateRewards(users[i]);
            rewards[users[i]] = userReward + currentReward;
            emit RewardAdded(users[i], currentReward);
        }
        lastUpdateTime = lastTimeRewardApplicable();
        nextDistributionDate = block.timestamp + 7 days;
        emit RewardsDurationUpdated(nextDistributionDate);

    }

    function deposit() public onlyOwner payable {

    }

    function withdraw() public {
        uint amount = address(this).balance;
        address owner = payable(msg.sender);
        (bool success, ) = owner.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    modifier updateReward(address account) {
        if (account != address(0)) {
            rewards[account] = 0 ;
        }
        _;
    }

    event RewardAdded(address indexed user, uint256 reward);
    event Staked(address indexed user, uint256[] tokenIds);
    event Unstaked(address indexed user, uint256[] tokenIds);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event RequestProfit(bytes32 indexed requestId, uint256 volume);
}