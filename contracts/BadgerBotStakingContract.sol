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
    uint256 private withdrawAmountThisMonth;
    address[] private depositThisMonthUsers;
    address[] private withdrawThisMonthUsers;
    // uint256 public lastDistributionTimestamp;

    // struct DepositRecord {
    //     uint256 deposit_amount;
    //     uint256 deposit_timestamp;
    // }

    struct StakedAsset {
        uint256 tokenId;
        uint256 stake_timestamp;
        bool staked;
        uint256 deposit_timestamp;
        uint256 allocation;
        bool deposited;
        bool enableWithdrawProfit;
        uint256 deposit_amount_this_month;
        uint256 withdraw_amount_this_month;
        // DepositRecord[] deposit_records;
    }

    mapping(address => StakedAsset) public stakedAssets;

    address[] public withdrawProfitRequestUsers;
    mapping(address => bool) public isWithdrawProfit;

    address[] private pendingWithdrawUsers;
    address[] private pendingWithdrawAllUsers;
    mapping(address => uint256) public pendingWithdrawAmount;
    uint256 public pendingWithdrawAmountTotal;
    uint256 public pendingWithdrawAllAllocationTotal;

    constructor(address payable _nftCollection, address _weth, address payable _team) {
        owner = msg.sender;
        nftCollection = BadgerBotPool(_nftCollection);
        weth = IERC20(_weth);
        teamAddress = _team;//Team Wallet Address
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


    function addExistingInvestors(address _investor, uint256 _depositAmount, uint256 _depositTimestamp) external payable onlyOwner {
        require(nftCollection.isWhitelisted(_investor), "Address is not in the whitelist");
        require(_depositAmount > 0, "Deposit amount must be greater than zero");
        require(_depositAmount == msg.value, "Correct ETH is not set to deposit.");

        StakedAsset storage asset = stakedAssets[_investor];

        uint256 _tokenId = nftCollection.tokenOfOwnerByIndex(_investor, 0);

        stakedAssets[_investor].tokenId = _tokenId;
        stakedAssets[_investor].stake_timestamp = _depositTimestamp;
        stakedAssets[_investor].staked = false;

        // DepositRecord memory newRecord = DepositRecord({
        //     deposit_amount: _depositAmount,
        //     deposit_timestamp: block.timestamp
        // });

        // stakedAssets[msg.sender].deposit_records.push(newRecord);

        uint256 ratio = getRatio();

        ( bool sent, ) = address(nftCollection).call{value: _depositAmount}("");
        require(sent, "Failed to send Ether");

        emit DepositReceived(_investor, _depositAmount);

        if (asset.allocation == 0) {
            asset.deposit_timestamp = block.timestamp;
            asset.deposited = true;
            asset.enableWithdrawProfit = false;
            isWithdrawProfit[_investor] = false;
        }

        uint256 depositAllocation = _depositAmount / ratio;
        asset.allocation += depositAllocation;
        allocationTotal += depositAllocation;
        asset.deposit_amount_this_month += _depositAmount;
        depositThisMonthUsers.push(_investor);
        depositAmountThisMonth += _depositAmount;

        emit Deposit(_investor,  _depositAmount);
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


    function deposit() public payable {
        StakedAsset storage asset = stakedAssets[msg.sender];
        require(asset.staked, 'user has no staked asset');
        require(msg.value > 0, "Deposit amount must be greater than zero");

        (uint256 ratio, uint256 fundsTotal) = getRatioTotalFunds();
        uint256 fundsUser = fundsTotal * asset.allocation;
        uint256 newTotalDeposit = fundsUser + msg.value;
        require(newTotalDeposit >= MIN_DEPOSIT && newTotalDeposit <= MAX_DEPOSIT, "Deposit amount is not within the allowed range");

        ( bool sent, ) = address(nftCollection).call{value: msg.value}("");
        require(sent, "Failed to send Ether");

        emit DepositReceived(msg.sender,  msg.value);
        
        // DepositRecord memory newRecord = DepositRecord({
        //     deposit_amount: msg.value,
        //     deposit_timestamp: block.timestamp
        // });

        // asset.deposit_records.push(newRecord);

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
        depositThisMonthUsers.push(msg.sender);
        depositAmountThisMonth += msg.value;

        emit Deposit(msg.sender,  msg.value);
    }



    ////////////////////////////////////////////////////////////
    //----------------------- Withdraw  ----------------------//
    ////////////////////////////////////////////////////////////


    function requestWithdraw(uint256 _withdrawFundsPercent) public nonReentrant {
        require(_withdrawFundsPercent > 0, "Withdraw percent must be greater than zero");
        require(stakedAssets[msg.sender].allocation > 0, "User has no staked asset");

        uint256 fundsUser = getUserFunds(msg.sender);
        if (fundsUser < 1 || _withdrawFundsPercent > MAX_WITHDRAW_PERCENT) {
            revert(string.concat("You can only request a withdrawal of less than ", MAX_WITHDRAW_PERCENT.toString(),"%."));
        }

        uint256 withdrawAmount = fundsUser * _withdrawFundsPercent;
        uint256 poolEthBalance = address(nftCollection).balance;

        if (poolEthBalance >= withdrawAmount) {
            _withdrawToUser(msg.sender, withdrawAmount);
        } else {
            _pendWithdrawAmount(msg.sender, withdrawAmount);
        }
    }

    function _pendWithdrawAmount(address _user, uint256 _amount) internal {
        pendingWithdrawAmount[_user] += _amount;
        pendingWithdrawAmountTotal += _amount;
        pendingWithdrawUsers.push(_user);
        emit WithdrawPending(_user, _amount);
    }

    function requestWithdrawAll() public nonReentrant {
        require(stakedAssets[msg.sender].allocation > 0, "User has no staked asset");

        uint256 fundsUser = getUserFunds(msg.sender);
        require(fundsUser < 1, "You can withdraw your all funds only when your funds is smaller than 1 ETH.");
        uint256 poolEthBalance = address(nftCollection).balance;
        if (poolEthBalance >= fundsUser) {
            _withdrawToUser(msg.sender, fundsUser);
        } else {
            _pendWithdrawAllAllocation(msg.sender);
        }
    }

    function _pendWithdrawAllAllocation(address _user) internal {
        pendingWithdrawAllAllocationTotal += stakedAssets[_user].allocation;
        pendingWithdrawAllUsers.push(_user);
        emit WithdrawAllPending(_user, stakedAssets[_user].allocation);
    } 

    function completePendingWithdraw() public nonReentrant {
        uint256 pendingAmount = getPendingAmountUser(msg.sender);

        uint256 poolEthBalance = address(nftCollection).balance;
        require(poolEthBalance >= pendingAmount, "Pool does not have enough ETH to fulfill pending withdrawal");

        _withdrawToUser(msg.sender, pendingAmount);
        pendingWithdrawAmount[msg.sender] = 0;
        pendingWithdrawAmountTotal = pendingWithdrawAmountTotal - pendingAmount;
        _removeFromPendingWithdrawUserList(msg.sender);
    }

    function completePendingWithdrawAll() public nonReentrant {
        require(_isPendingWithdrawAllUserExist(msg.sender), "You didn't request withdrawing all your funds.");

        uint256 poolEthBalance = address(nftCollection).balance;
        uint256 fundsUser = getUserFunds(msg.sender);
        require(poolEthBalance >= fundsUser, "Pool does not have enough ETH to fulfill pending withdrawal");

        _withdrawToUser(msg.sender, fundsUser);
        pendingWithdrawAllAllocationTotal = pendingWithdrawAllAllocationTotal - stakedAssets[msg.sender].allocation;
        _removeFromPendingWithdrawAllUserList(msg.sender);
    }

    function getPendingAmountUser(address _user) public view returns (uint256) {
        require(_isPendingWithdrawUserExist(_user), "There isn't any pending withdraw funds of you");
        return pendingWithdrawAmount[_user];
    }

    function _isPendingWithdrawUserExist(address _address) internal view returns (bool) {
        return _isAddressInArray(_address, pendingWithdrawUsers);
    }

    function _removeFromPendingWithdrawUserList(address _address) internal {
        _removeAddressFromArray(_address, pendingWithdrawUsers);
    }

    function _isPendingWithdrawAllUserExist(address _address) internal view returns (bool) {
        return _isAddressInArray(_address, pendingWithdrawAllUsers);
    }

    function _removeFromPendingWithdrawAllUserList(address _address) internal {
        _removeAddressFromArray(_address, pendingWithdrawAllUsers);
    }

    function _withdrawToUser(address _user, uint256 _amount) internal {
        require(address(nftCollection).balance > _amount, "Insufficient ETH balance to withdraw");

        uint256 ratio = getRatio();
        StakedAsset storage asset = stakedAssets[_user];
        nftCollection.withdrawByStakingContract(_user, _amount);
        emit WithdrawUserFunds(_user, _amount, block.timestamp);

        uint256 withdrawAllocation = _amount / ratio;
        asset.allocation = asset.allocation - withdrawAllocation;
        allocationTotal = allocationTotal - withdrawAllocation;
        asset.withdraw_amount_this_month += _amount;
        withdrawThisMonthUsers.push(_user);
        withdrawAmountThisMonth += _amount;

        if (asset.allocation == 0) {
            asset.deposited = false;
            asset.enableWithdrawProfit = false;
            _cancelWithdrawProfitRequest(_user);
        }
    }


    ////////////////////////////////////////////////////////////
    //------------------- Reward Distribution ----------------//
    ////////////////////////////////////////////////////////////


    function rewardDistribution() external onlyOwner nonReentrant {
        require(_isFirstDayOfMonth(), "Today is not the 1st of the month");

        uint256 fundsTotalCurrent = getTotalFunds();
        uint256 profitTotal = fundsTotalCurrent - fundsTotalOld - depositAmountThisMonth + withdrawAmountThisMonth;

        if (profitTotal > 0) {
            uint256 profitTeam = profitTotal * TEAM_SHARE / 100;
            
            teamAddress.transfer(profitTeam);
            emit WithdrawTeamProfit(profitTeam, block.timestamp);

            fundsTotalCurrent = fundsTotalCurrent - profitTeam;
        }

        uint256 ratio = fundsTotalCurrent / allocationTotal;

        //--------------  Withdraw Profit  ------------//
        uint256 allocationWithdrawProfit = 0;
        uint256 amountWithdrawProfit = 0;

        for (uint256 i = 0; i < withdrawProfitRequestUsers.length; i++) {
            address user = withdrawProfitRequestUsers[i];
            StakedAsset storage asset = stakedAssets[user];

            uint256 allocationUser = asset.allocation;
            uint256 fundsUserCurrent = allocationUser * ratio;
            uint256 fundsUserOld = allocationUser * ratioOld;
            uint256 profitUser = fundsUserCurrent - fundsUserOld - asset.deposit_amount_this_month;

            if (profitUser > 0) {
                nftCollection.withdrawByStakingContract(user, profitUser);
                emit WithdrawUserProfit(user, profitUser, block.timestamp);
                
                uint256 allocationUserNew = allocationUser - (profitUser / ratio);
                allocationWithdrawProfit += (profitUser / ratio);
                amountWithdrawProfit += profitUser;
                asset.allocation = allocationUserNew;
            }

            isWithdrawProfit[user] = false;
        }

        allocationTotal = allocationTotal - allocationWithdrawProfit;
        fundsTotalCurrent = fundsTotalCurrent - amountWithdrawProfit;
        // fundsTotalCurrent = allocationTotal * ratio;

        delete withdrawProfitRequestUsers;

    //------------ Reset Old State and Temps States ----------------//
        fundsTotalOld = fundsTotalCurrent;
        allocationTotalOld = allocationTotal;
        ratioOld = fundsTotalOld / allocationTotalOld;
        _resetTempValues();

        // lastDistributionTimestamp = block.timestamp;
        emit RewardsDistributed(block.timestamp);
    }

    function _resetTempValues() internal {
        _resetDepositThisMonthUsers();
        _resetWithdrawThisMonthUsers();
    }

    function _resetDepositThisMonthUsers() internal {
        depositAmountThisMonth = 0;

        for (uint256 index = 0; index < depositThisMonthUsers.length; index++) {
            stakedAssets[depositThisMonthUsers[index]].deposit_amount_this_month = 0;
        }
        delete depositThisMonthUsers;
    }

    function _resetWithdrawThisMonthUsers() internal {
        withdrawAmountThisMonth = 0;

        for (uint256 index = 0; index < withdrawThisMonthUsers.length; index++) {
            stakedAssets[withdrawThisMonthUsers[index]].withdraw_amount_this_month = 0;
        }
        delete withdrawThisMonthUsers;
    }

 
    ////////////////////////////////////////////////////////////
    //--------------- Withdraw Profit Request ----------------//
    ////////////////////////////////////////////////////////////


    function requestWithdrawProfit() external {
        require(stakedAssets[msg.sender].enableWithdrawProfit, "You can request withdraw profit since next month.");
        require(isWithdrawProfit[msg.sender] == false, "You've already request withdraw profit.");
        withdrawProfitRequestUsers.push(msg.sender);
        isWithdrawProfit[msg.sender] = true;

        emit RequestWithdrawProfit(msg.sender);
    }

    function cancelWithdrawProfitRequest() external {
        _cancelWithdrawProfitRequest(msg.sender);
    }

    function _cancelWithdrawProfitRequest(address _user) internal {
        require(_withdrawProfitRequestUserExist(_user), "You didn't request withdraw profit.");
        _removeAddressFromArray(_user, withdrawProfitRequestUsers);
        isWithdrawProfit[_user] = false;

        emit CancelWithdrawProfit(_user);
    }
    
    function getUserWithdrawProfitRequestInfo(address _user) public view returns (bool) {
        return isWithdrawProfit[_user];
    }
    
    function _withdrawProfitRequestUserExist(address _address) internal view returns (bool) {
        return _isAddressInArray(_address, withdrawProfitRequestUsers);
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

    function getTotalFunds() public view returns (uint256) {
        uint256 ethBalance = address(nftCollection).balance;
        uint256 wethBalance = nftCollection.getWethBalance();
        uint256 assetsValue = nftCollection.getTotalAssetsValue();
        uint256 fundsTotal = ethBalance + wethBalance + assetsValue;
        return fundsTotal;
    }

    function getRatio() public view returns (uint256) {
        if (allocationTotal == 0) {
            return 1;
        } else {
            uint256 fundsTotal = getTotalFunds();
            return fundsTotal/allocationTotal;
        }
    }

    function getRatioTotalFunds() public view returns (uint256, uint256) {
        uint256 fundsTotal = getTotalFunds();
        if (allocationTotal == 0) {
            return (1, fundsTotal);
        } else {
            return (fundsTotal/allocationTotal, fundsTotal);
        }
    }

    function userStakeInfo(address _user)
        public
        view
        returns (StakedAsset memory)
    {
        return stakedAssets[_user];
    }

    function getUserFunds(address _user) public view returns (uint256) {
        uint256 fundsTotal = getTotalFunds();
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
        require(_isAddressInArray(_user, users), "User is not in the Users List.");
        _removeAddressFromArray(_user, users);
    }

    function _isFirstDayOfMonth() internal view returns (bool) {
        uint256 currentTime = block.timestamp;
       (, , uint256 day) = DateTime.timestampToDate(currentTime);
        return day == 1;
    }

    function _isAddressInArray(address _address, address[] memory _array) internal pure returns (bool) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function _removeAddressFromArray(address _address, address[] storage _array) internal {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _address) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
        }
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
    event DepositReceived(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 timestamp);
    event WithdrawTeamProfit(uint256 profitTeam, uint256 timestamp);
    event WithdrawUserProfit(address indexed user, uint256 profit, uint256 timestamp);
    event WithdrawUserFunds(address indexed user, uint256 funds, uint256 timestamp);
    event WithdrawPending(address indexed user, uint256 funds);
    event WithdrawAllPending(address indexed user, uint256 allocation);
    event PendingWithdrawCompleted(address indexed user, uint256 funds, uint256 timestamp);
    event RequestWithdrawProfit(address indexed user);
    event CancelWithdrawProfit(address indexed user);
}