// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./BadgerBotPool.sol";
import "./DateTime.sol";

/// @author Shola Ayeni, Hiroki Hara
/// @title BadgerBot NFT Staking Contract
/// @notice Staking Contract that uses the Openzepellin Staking model to distribute ERC20 token rewards in a dynamic way,
/// proportionally based on the amount of ERC721 tokens staked by each staker at any given time.

contract BadgerBotStakingContract is ReentrancyGuard {
    using Strings for uint256;

    BadgerBotPool public nftCollection;
    IERC20 public weth;
    // IERC20 public beth;

    address public owner;
    address payable public teamAddress;

    uint256 public totalStakedSupply;
    address[] private users;
    // uint public totalSupply = 5;


    uint256 public MIN_DEPOSIT = 1 ether;
    uint256 public MAX_DEPOSIT = 5 ether;
    uint256 public MAX_WITHDRAW_PERCENT = 50;
    uint256 public TEAM_SHARE = 20;
    uint256 public INITIAL_TAX = 15;
    uint256 public SLOP_TAX = 1;
    uint256 public STAGNANT_TAX = 3;


    uint256 public fundsTotalOld;
    uint256 public allocationTotalOld;
    uint256 public ratioOld;
    
    uint256 public allocationTotal;
    uint256 private depositAmountThisMonth;
    // uint256 public lastDistributionTimestamp;

    struct DepositRecord {
        uint256 deposit_amount;
        uint256 deposit_timestamp;
    }

    struct StakedAsset {
        uint256 tokenId;
        uint256 stake_timestamp;
        bool staked;
        uint256 deposit_timestamp;
        uint256 allocation;
        bool deposited;
        bool enableWithdrawProfit;
        uint256 deposit_amount_this_month;
        DepositRecord[] deposit_records;
    }

    mapping(address => StakedAsset) public stakedAssets;

    address[] public withdrawProfitRequestUsers;
    mapping(address => bool) public isWithdrawProfit;
    // mapping(address => uint256) private rewards;

    address[] private withdrawRequestUsers;
    mapping (address => uint256) public withdrawFundsPercents;

    constructor(address payable _nftCollection, address _weth) {
        owner = msg.sender;
        teamAddress = payable(0x6360A1E7dFe205397d7EF463cb28f16Fbdaa2D24);//Team Wallet Address
        nftCollection = BadgerBotPool(_nftCollection);
        weth = IERC20(_weth);
    }


    ////////////////////////////////////////////////////////////
    //--------------------- Set Constants --------------------//
    ////////////////////////////////////////////////////////////


    function setDepositRange(uint256 _min, uint256 _max) external onlyOwner {
        MIN_DEPOSIT = _min;
        MAX_DEPOSIT = _max;
    }

    function setMaxWithdrawPercent(uint256 _maxWithdraw) external onlyOwner {
        MAX_WITHDRAW_PERCENT = _maxWithdraw;
    }

    function setTeamSharePercent(uint256 _teamShare) external onlyOwner {
        TEAM_SHARE = _teamShare;
    }

    function setInitialTaxPercent(uint256 _initialTax) public onlyOwner {
        INITIAL_TAX = _initialTax;
    }

    function setSlopTaxPercent(uint256 _slopTax) public onlyOwner {
        SLOP_TAX = _slopTax;
    }

    function  setStagnantTaxPercent(uint256 _stagnantTax) public onlyOwner {
        STAGNANT_TAX = _stagnantTax;
    }

    function setWithdrawTaxParams(uint256 _initialTax, uint256 _slopTax, uint256 _stagnantTax) external onlyOwner {
        INITIAL_TAX = _initialTax;
        SLOP_TAX = _slopTax;
        STAGNANT_TAX = _stagnantTax;
    }


    ////////////////////////////////////////////////////////////
    //--------------- NFT Staking and Unstaking --------------//
    ////////////////////////////////////////////////////////////


    function addExistingInvestors(address _investor, uint256 _depositAmount, uint256 _depositTimestamp) external onlyOwner {
        require(nftCollection.isWhitelisted(_investor), "Address is not in the whitelist");
        require(_depositAmount > 0, "Deposit amount must be greater than zero");

        uint256 _tokenId = nftCollection.tokenOfOwnerByIndex(_investor, 0);

        stakedAssets[_investor].tokenId = _tokenId;
        stakedAssets[_investor].stake_timestamp = _depositTimestamp;
        stakedAssets[_investor].staked = false;

        DepositRecord memory newRecord = DepositRecord({
            deposit_amount: _depositAmount,
            deposit_timestamp: block.timestamp
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
        _removeUser(msg.sender);
        emit Unstaked(msg.sender, tokenId);
    }


    ////////////////////////////////////////////////////////////
    //------------------------ Deposit -----------------------//
    ////////////////////////////////////////////////////////////  


    function deposit(uint256 _assetsValue) public payable {
        StakedAsset storage asset = stakedAssets[msg.sender];
        require(asset.staked, 'user has no staked asset');
        require(msg.value > 0, "Deposit amount must be greater than zero");

        uint256 fundsTotal = getTotalFunds(_assetsValue);
        uint256 fundsUser = fundsTotal * asset.allocation;
        uint256 newTotalDeposit = fundsUser + msg.value;
        require(newTotalDeposit >= MIN_DEPOSIT && newTotalDeposit <= MAX_DEPOSIT, "Deposit amount is not within the allowed range");

        ( bool sent, ) = address(nftCollection).call{value: msg.value}("");
        require(sent, "Failed to send Ether");
        
        uint256 ratio = fundsTotal / allocationTotal;
        DepositRecord memory newRecord = DepositRecord({
            deposit_amount: msg.value,
            deposit_timestamp: block.timestamp
        });

        stakedAssets[msg.sender].deposit_records.push(newRecord);

        if (asset.allocation == 0) {
            asset.deposit_timestamp = block.timestamp;
            asset.deposited = true;
            asset.enableWithdrawProfit = false;
            isWithdrawProfit[msg.sender] = false;
        }

        uint256 depositAllocation = msg.value / ratio;
        asset.allocation += depositAllocation;
        allocationTotal += depositAllocation;
        asset.deposit_amount_this_month += msg.value;
        depositAmountThisMonth += msg.value;

        emit Deposit(msg.sender,  msg.value);
    }


    ////////////////////////////////////////////////////////////
    //------------------- Reward Distribution ----------------//
    ////////////////////////////////////////////////////////////


    function rewardDistribution(uint256 _assetsValue) external onlyOwner nonReentrant {
        require(_isFirstDayOfMonth(), "Today is not the 1st of the month");
        // require(block.timestamp > lastDistributionTimestamp + 30 days, "Already distributed this month");

        uint256 fundsTotalCurrent = getTotalFunds(_assetsValue);
        uint256 profitTotal = fundsTotalCurrent - fundsTotalOld - depositAmountThisMonth;

        if (profitTotal > 0) {
            uint256 profitTeam = profitTotal * TEAM_SHARE / 100;
            
            teamAddress.transfer(profitTeam);
            emit WithdrawTeamProfit(profitTeam, block.timestamp);

            fundsTotalCurrent = fundsTotalCurrent + profitTeam;
        }

        uint256 ratio = fundsTotalCurrent / allocationTotal;

        //--------------  Withdraw Profit  ------------//
        uint256 allocationWithdrawProfit = 0;
        // uint256 amountWithdrawProfit = 0;

        for (uint256 i = 0; i < withdrawProfitRequestUsers.length; i++) {
            address user = withdrawProfitRequestUsers[i];
            StakedAsset storage asset = stakedAssets[user];

            uint256 allocationUser = asset.allocation;
            uint256 fundsUserCurrent = allocationUser * ratio;
            uint256 fundsUserOld = allocationUser * ratioOld;
            uint256 profitUser = fundsUserCurrent - fundsUserOld - asset.deposit_amount_this_month;

            if (profitUser > 0) {
                payable(user).transfer(profitUser);
                emit WithdrawUserProfit(user, profitUser, block.timestamp);
                
                uint256 allocationUserNew = allocationUser - (profitUser / ratio);
                allocationWithdrawProfit += (profitUser / ratio);
                // amountWithdrawProfit += profitUser;
                asset.allocation = allocationUserNew;
            }

            isWithdrawProfit[user] = false;
        }

        allocationTotal = allocationTotal - allocationWithdrawProfit;
        // fundsTotalCurrent = fundsTotalCurrent - amountWithdrawProfit;
        fundsTotalCurrent = allocationTotal * ratio;

        delete withdrawProfitRequestUsers;
        
    //-------------------- Withdraw Request -----------------------//


    //------------ Reset Old State and Temps States ----------------//
        fundsTotalOld = fundsTotalCurrent;
        allocationTotalOld = allocationTotal;
        ratioOld = ratio;


        // lastDistributionTimestamp = block.timestamp;
        emit RewardsDistributed(block.timestamp);
    }

    ////////////////////////////////////////////////////////////
    //------------------- Withdraw Request -------------------//
    ////////////////////////////////////////////////////////////

    
    function requestWithdraw(uint256 _withdrawFundsPercent, uint256 _assetsValue) external {
        uint256 fundsUser = getUserFunds(msg.sender, _assetsValue);
        if (fundsUser > 1 && _withdrawFundsPercent > MAX_WITHDRAW_PERCENT) {
            revert(string.concat("You can only request a withdrawal of less than ", MAX_WITHDRAW_PERCENT.toString(),"%."));
        }

        if (fundsUser <= 1 && _withdrawFundsPercent != 100) {
            revert("You can only request a withdrawal of 100%.");
        }

        bool existed = false;
        for (uint256 i = 0; i < withdrawRequestUsers.length; i++) {
            if(withdrawRequestUsers[i] != msg.sender) {
                withdrawFundsPercents[msg.sender] = _withdrawFundsPercent;
                existed = true;
                break;
            }
        }

        if (existed) {
            return;
        }

        withdrawRequestUsers.push(msg.sender);
        withdrawFundsPercents[msg.sender] = _withdrawFundsPercent;
    } 

    // function removeFromWithdrawFundsList(uint256 _cancelWithdrawPercent) external {
    //     require(_withdrawRequestUserExist(msg.sender), "There isn't any withdraw request of you");
    //     require(_cancelWithdrawPercent > 0, "The withdraw amount you wish to cancel can not be 0");
    //     withdrawFundsPercents[msg.sender] = _cancelWithdrawPercent;
    // }

    function cancelWithdrawRequest() external {
        require(_withdrawRequestUserExist(msg.sender), "There isn't any withdraw request of you");
        for (uint256 i = 0; i < withdrawRequestUsers.length; i++) {
            if (withdrawRequestUsers[i] == msg.sender) {
                withdrawRequestUsers[i] = withdrawRequestUsers[withdrawRequestUsers.length - 1];
                withdrawRequestUsers.pop();
            }
        }
        withdrawFundsPercents[msg.sender] = 0;
    }

    function getUserWithdrawRequestInfo(address _user) public view returns (uint256) {
        require(_withdrawRequestUserExist(_user), "There isn't any withdraw request of you");
        return withdrawFundsPercents[_user];
    }

    function _withdrawRequestUserExist(address _address) internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (withdrawRequestUsers[i] == _address) {
                return true;
            }
        }
        return false;
    }

 
    ////////////////////////////////////////////////////////////
    //--------------- Withdraw Profit Request ----------------//
    ////////////////////////////////////////////////////////////


    function requestWithdrawProfit() external {
        require(isWithdrawProfit[msg.sender] == false, "You've already request withdraw profit.");
        withdrawProfitRequestUsers.push(msg.sender);
        isWithdrawProfit[msg.sender] = true;
    }

    function cancelWithdrawProfitRequest() external {
        require(_withdrawProfitRequestUserExist(msg.sender), "You didn't request withdraw profit.");
        for (uint256 i = 0; i < withdrawProfitRequestUsers.length; i++) {
            if (withdrawProfitRequestUsers[i] == msg.sender) {
                withdrawProfitRequestUsers[i] = withdrawProfitRequestUsers[withdrawProfitRequestUsers.length - 1];
                withdrawProfitRequestUsers.pop();
            }
        }
        isWithdrawProfit[msg.sender] = false;
    }
    
    function getUserWithdrawProfitRequestInfo(address _user) public view returns (bool) {
        return isWithdrawProfit[_user];
    }
    
    function _withdrawProfitRequestUserExist(address _address) internal view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (withdrawProfitRequestUsers[i] == _address) {
                return true;
            }
        }
        return false;
    }


    ////////////////////////////////////////////////////////////
    //-------------------- Basic Functions -------------------//
    ////////////////////////////////////////////////////////////


    // function withdrawForOwner() public onlyOwner nonReentrant {
    //     uint256 balance = address(this).balance;
    //     require(balance > 0, "Balance is zero");
    //     payable(owner).transfer(balance);
    // }
  
    function getUsers() external view returns (address[] memory) {
        return users;
    }

    function getUserStakeInfo(address _user) public view returns (StakedAsset memory) {
        return stakedAssets[_user];
    }

    function getTotalFunds(uint256 _assetsValue) public view returns (uint256) {
        uint256 ethBalance = address(nftCollection).balance;
        uint256 wethBalance = getWethBalance();
        uint256 fundsTotal = ethBalance + wethBalance + _assetsValue;
        return fundsTotal;
    }

    function getWethBalance() public view returns (uint256) {
        return weth.balanceOf(address(nftCollection));
    }

    function userStakeInfo(address _user)
        public
        view
        returns (StakedAsset memory)
    {
        return stakedAssets[_user];
    }

    function getUserFunds(address _user, uint256 _assetsValue) public view returns (uint256) {
        uint256 fundsTotal = getTotalFunds(_assetsValue);
        uint256 allocationUser = stakedAssets[_user].allocation;
        uint256 fundsUser = fundsTotal * allocationUser / allocationTotal;

        return fundsUser;
    }

    function userExist(address _address) public view returns (bool) {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function _removeUser(address _user) internal {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _user) {
                users[i] = users[users.length - 1];
                users.pop();
            }
        }
    }

    function _isFirstDayOfMonth() internal view returns (bool) {
        uint256 currentTime = block.timestamp;
       (, , uint256 day) = DateTime.timestampToDate(currentTime);
        return day == 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }


    ////////////////////////////////////////////////////////////
    //-----------------------  Event  ------------------------//
    ////////////////////////////////////////////////////////////

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Deposit(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 timestamp);
    event WithdrawTeamProfit(uint256 profitTeam, uint256 timestamp);
    event WithdrawUserProfit(address indexed user, uint256 profit, uint256 timestamp);
}