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

    struct StakedAsset {
        uint256 tokenId;
        uint256 depositAmount;
        uint256 depositTimestamp;
        uint256 stakeTimestamp;
        bool staked;
        bool deposited;
    }

    // Deposit min = 1 ETH, deposit max = 5 ETH. 

    uint256 public MIN_DEPOSIT = 1000000000000000000;
    uint256 public MAX_DEPOSIT = 5000000000000000000;

    mapping(address => uint256) private rewards;
    mapping(address => StakedAsset) public stakedAssets;
    address[] public whitelist;

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

    function editDepositRange(uint256 _min, uint256 _max) external {
        MIN_DEPOSIT = _min;
        MAX_DEPOSIT = _max;
    }

    function addToWhiteList(address[] memory _whitelist) external {
        for (uint256 i = 0; i < _whitelist.length; i++) {
            whitelist.push(_whitelist[i]);
        }
    }

     function isWhitelisted(address _address) public view returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function addExistingInvestors(address _investor, uint256 _tokenId, uint256 _depositAmount, uint256 _depositTimestamp) external {
        require(isWhitelisted(_investor), "Address is not in the whitelist");
        require(!stakedAssets[_investor].staked, "Address already has a staked asset");

        stakedAssets[_investor] = StakedAsset({
            tokenId: _tokenId,
            depositAmount: _depositAmount,
            depositTimestamp: _depositTimestamp,
            stakeTimestamp: _depositTimestamp, 
            staked: true,
            deposited: true
        });

        totalStakedSupply += 1;
        users.push(_investor);
    }

    function stake(uint256 tokenId) external {
        require(nftCollection.balanceOf(msg.sender) > 0, 'user has no NFT pass');
        require(stakedAssets[msg.sender].staked == false, 'user already has staked asset');
        nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        totalStakedSupply += 1;
        
        stakedAssets[msg.sender].tokenId = tokenId;
        stakedAssets[msg.sender].stakeTimestamp = block.timestamp;
        stakedAssets[msg.sender].staked = true;
        users.push(msg.sender);
        emit Staked(msg.sender, tokenId);
    }

    function unstake(uint256 tokenId) public nonReentrant {
        require(stakedAssets[msg.sender].staked == true, 'user has no staked asset');
        nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

        totalStakedSupply -= 1;
        stakedAssets[msg.sender].tokenId = 0;
        stakedAssets[msg.sender].stakeTimestamp = 0;
        removeUser(msg.sender);
        emit Unstaked(msg.sender, tokenId);
    }

    function addFunds() public payable {
        require(stakedAssets[msg.sender].staked == true, 'user has no staked asset');
        require(MIN_DEPOSIT >= msg.value, 'deposit amount is less than minimum deposit');
        require(MAX_DEPOSIT <= msg.value, 'deposit amount is more than maximum deposit');

        uint256 prevAmount = stakedAssets[msg.sender].depositAmount;
        uint256 newAmount = prevAmount +  msg.value;

        stakedAssets[msg.sender].depositAmount = newAmount;
        stakedAssets[msg.sender].depositTimestamp = block.timestamp;
        stakedAssets[msg.sender].deposited = true;

        emit Deposit(msg.sender,  msg.value);
    }

    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "Balance is zero");
        payable(owner()).transfer(balance);
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


    function userStakeInfo(address _user)
        public
        view
        returns (StakedAsset memory)
    {
        return stakedAssets[_user];
    }

    event RewardAdded(address indexed user, uint256 reward);
    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event RequestProfit(bytes32 indexed requestId, uint256 volume);
    event Deposit(address indexed user, uint256 amount);
}