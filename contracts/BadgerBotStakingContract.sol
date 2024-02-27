// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BadgerBotPool.sol";

/// @author Shola Ayeni
/// @title BadgerBot NFT Staking Contract
/// @notice Staking Contract that uses the Openzepellin Staking model to distribute ERC20 token rewards in a dynamic way,
/// proportionally based on the amount of ERC721 tokens staked by each staker at any given time.

contract BadgerBotStakingContract is ERC721Holder, ReentrancyGuard {

    BadgerBotPool public nftCollection;

    uint256 public totalStakedSupply;
    address[] private users;
    uint public totalSupply = 5;

    struct StakedAsset {
        uint256 tokenId;
        uint256 deposit_amount;
        uint256 deposit_timestamp;
        uint256 stake_timestamp;
        bool staked;
        bool deposited;
        uint256 deposit_tax;
    }

    address public owner;
    uint256 public MIN_DEPOSIT = 1 ether;
    uint256 public MAX_DEPOSIT = 5 ether;

    mapping(address => uint256) private rewards;
    mapping(address => StakedAsset) public stakedAssets;

    constructor(address _nftCollection) {
        owner = msg.sender;
        nftCollection = BadgerBotPool(_nftCollection);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
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

    function addExistingInvestors(address _investor, uint256 _depositAmount, uint256 _depositTimestamp) external onlyOwner() {
        require(nftCollection.isWhitelisted(_investor), "Address is not in the whitelist");

        uint256 _tokenId = nftCollection.tokenOfOwnerByIndex(_investor, 0);
        stakedAssets[_investor] = StakedAsset({
            tokenId: _tokenId,
            deposit_amount: _depositAmount,
            deposit_timestamp: _depositTimestamp,
            stake_timestamp: _depositTimestamp, 
            staked: false,
            deposited: true,
            deposit_tax: _depositAmount /10
        });
    }

    function stake(uint256 tokenId) external {
        require(nftCollection.balanceOf(msg.sender) > 0, 'user has no NFT pass');
        require(stakedAssets[msg.sender].staked == false, 'user already has staked asset');
        nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        totalStakedSupply += 1;
        
        stakedAssets[msg.sender].tokenId = tokenId;
        stakedAssets[msg.sender].stake_timestamp = block.timestamp;
        stakedAssets[msg.sender].staked = true;
        users.push(msg.sender);
        emit Staked(msg.sender, tokenId);
    }

    function unstake(uint256 tokenId) public nonReentrant {
        require(stakedAssets[msg.sender].staked == true, 'user has no staked asset');
        nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

        totalStakedSupply -= 1;
        stakedAssets[msg.sender].tokenId = 0;
        stakedAssets[msg.sender].stake_timestamp = 0;
        removeUser(msg.sender);
        emit Unstaked(msg.sender, tokenId);
    }

    function deposit() public payable {
        require(stakedAssets[msg.sender].staked, 'user has no staked asset');
        require(msg.value >= MIN_DEPOSIT && msg.value <= MAX_DEPOSIT, "Deposit amount is not within the allowed range");

        uint256 prevAmount = stakedAssets[msg.sender].deposit_amount;
        uint256 newAmount = prevAmount +  msg.value;
        uint256 prevDepositTax = stakedAssets[msg.sender].deposit_tax;
        uint256 newDepositTax = prevDepositTax + (msg.value / 10);

        stakedAssets[msg.sender].deposit_amount = newAmount;
        stakedAssets[msg.sender].deposit_timestamp = block.timestamp;
        stakedAssets[msg.sender].deposited = true;
        stakedAssets[msg.sender].deposit_tax = newDepositTax;

        emit Deposit(msg.sender,  msg.value);
    }

    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "Balance is zero");
        payable(owner).transfer(balance);
    }

    function userStakeInfo(address _user)
        public
        view
        returns (StakedAsset memory)
    {
        return stakedAssets[_user];
    }

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Deposit(address indexed user, uint256 amount);
}