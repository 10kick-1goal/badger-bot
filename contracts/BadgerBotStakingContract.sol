// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BadgerBotPool.sol";

/// @author Shola Ayeni, Hiroki Hara
/// @title BadgerBot NFT Staking Contract
/// @notice Staking Contract that uses the Openzepellin Staking model to distribute ERC20 token rewards in a dynamic way,
/// proportionally based on the amount of ERC721 tokens staked by each staker at any given time.

contract BadgerBotStakingContract is ReentrancyGuard {

    BadgerBotPool public nftCollection;

    uint256 public totalStakedSupply;
    address[] private users;
    uint public totalSupply = 5;

    struct DepositRecord {
        uint256 deposit_amount;
        uint256 deposit_timestamp;
        uint256 deposit_tax;
        bool deposited;
    }

    struct StakedAsset {
        uint256 tokenId;
        uint256 stake_timestamp;
        bool staked;
        uint256 deposit_amount_all;
        uint256 deposit_tax_all;
        bool deposited;
        DepositRecord[] deposit_records;
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

    function editDepositRange(uint256 _min, uint256 _max) external onlyOwner {
        MIN_DEPOSIT = _min;
        MAX_DEPOSIT = _max;
    }

    function addExistingInvestors(address _investor, uint256 _depositAmount, uint256 _depositTimestamp) external onlyOwner {
        require(nftCollection.isWhitelisted(_investor), "Address is not in the whitelist");
        require(_depositAmount > 0, "Deposit amount must be greater than zero");

        uint256 _tokenId = nftCollection.tokenOfOwnerByIndex(_investor, 0);

        stakedAssets[_investor].tokenId = _tokenId;
        stakedAssets[_investor].stake_timestamp = _depositTimestamp;
        stakedAssets[_investor].staked = false;

        DepositRecord memory newRecord = DepositRecord({
            deposit_amount: _depositAmount,
            deposit_timestamp: block.timestamp,
            deposit_tax: _depositAmount / 10,
            deposited: false
        });

        stakedAssets[msg.sender].deposit_records.push(newRecord);
    }

    function stake(uint256 tokenId) external {
        require(nftCollection.balanceOf(msg.sender) > 0, 'user has no NFT pass');
        require(stakedAssets[msg.sender].tokenId == tokenId, 'user is not the owner of this nft');
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
        require(stakedAssets[msg.sender].tokenId == tokenId, 'user is not the owner of this asset');
        nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

        totalStakedSupply -= 1;
        stakedAssets[msg.sender].tokenId = 0;
        stakedAssets[msg.sender].stake_timestamp = 0;
        removeUser(msg.sender);
        emit Unstaked(msg.sender, tokenId);
    }

    function deposit() public payable {
        require(stakedAssets[msg.sender].staked, 'user has no staked asset');
        require(msg.value > 0, "Deposit amount must be greater than zero");

        uint256 newTotalDeposit = stakedAssets[msg.sender].deposit_amount_all + msg.value;
        require(newTotalDeposit >= MIN_DEPOSIT && newTotalDeposit <= MAX_DEPOSIT, "Deposit amount is not within the allowed range");

        DepositRecord memory newRecord = DepositRecord({
            deposit_amount: msg.value,
            deposit_timestamp: block.timestamp,
            deposit_tax: msg.value / 10,
            deposited: false
        });

        stakedAssets[msg.sender].deposit_records.push(newRecord);
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

    function depositToPool() external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            StakedAsset storage asset = stakedAssets[user];

            for (uint256 j = 0; j < asset.deposit_records.length; j++) {
                if (!asset.deposit_records[j].deposited) {
                    uint256 amount = asset.deposit_records[j].deposit_amount;
                    uint256 tax = asset.deposit_records[j].deposit_tax;

                    payable(address(nftCollection)).transfer(amount);

                    asset.deposit_amount_all += amount;
                    asset.deposit_tax_all += tax;
                    asset.deposit_records[j].deposited = true;

                    if (j == 0) {
                        asset.deposited = true;
                    }

                    emit DepositToPool(user, amount, tax);
                }
            }
        }
    }

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Deposit(address indexed user, uint256 amount);
    event DepositToPool(address indexed user, uint256 amount, uint256 tax);
}