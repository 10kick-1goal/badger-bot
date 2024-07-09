// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract BadgerBotPool is
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ERC721Burnable,
    ReentrancyGuard,
    Ownable
{
    using Strings for uint256;

    // ============ 1.  Property Variables  // ============

    string baseURI;
    string public baseExtension = ".json";
    string public baseImage = ".webp";
    uint256 private _nextTokenId = 1;
    uint256 public MINT_PRICE = 0 ether;
    uint256 public MAX_SUPPLY = 100;

    address public bot;
    address public stakingContract;
    IWETH public weth;

    bool public publicMintOpen = false;

    mapping(address => bool) public whitelist;
    address[] public whitelistedAddresses;

    uint256 public maxMintPerWalletPublicMint = 1;

    mapping(address => uint256) public mintedCount;

    //----------   NFT Fliping Related Varialbles   -------//
    struct FlipNFT {
        address collectionAddress;
        uint256 tokenId;
        uint256 price;
        string metadata;
    }

    FlipNFT[] private nfts;
    mapping(address => mapping(uint256 => uint256)) private nftIndex; // collectionAddress => tokenId => index in nfts array
    mapping(address => mapping(uint256 => bool)) private nftExists; // collectionAddress => tokenId => existence check


    // ============ 2.  Lifecycle Methods  // ============

    constructor(
        address _bot, 
        address _weth,
        string memory _initBaseURI
    ) ERC721("Badger Bot Pool", "BADGER")  Ownable(msg.sender) {
        bot = _bot;
        weth = IWETH(_weth);
        stakingContract = address(0);
        setBaseURI(_initBaseURI);

        addToWhitelist(address(0x297122b6514a9A857830ECcC6C41F1803963e516));
        addToWhitelist(address(0xC95449734dDa7ac6d494a1077Ca7f1773be4F38D));
        addToWhitelist(address(0x9F7496082F6bB1D27B84BE9BB10A423A1A4d9A1F));
        addToWhitelist(address(0x3d8e88d73297157C6125E76ec6f92BABAE2eC949));
        addToWhitelist(address(0xda6Fb0F91e321bB66cDE6eD92803A2BD8f3e8ac6));
    }

    function setMintFee(uint256 _mintFee) external onlyOwner {
        MINT_PRICE = _mintFee;
    }

    function tokenURI(uint256 _tokenId) 
        public 
        view 
        override 
        returns (string memory) 
    {
        require(_ownerOf(_tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
        
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0
            ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), baseExtension))
            : "";
    }

    function toImage(uint256 tokenId) internal view returns (string memory) {
        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0
            ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseImage))
            : "";
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function getBaseURI() external view returns (string memory) {
        return _baseURI();
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function addAddressesToWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            addToWhitelist(addr);
        }
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
        if (!_isAddressInArray(_address, whitelistedAddresses)) {
            whitelistedAddresses.push(_address);
        }  

        emit AddToWhitelist(_address, block.timestamp);
    }

    function removeUsersFromWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            removeFromWhitelist(addr);
        }
    }

    function removeFromWhitelist(address _address) public onlyOwner {
        require(_isAddressInArray(_address, whitelistedAddresses), "You are not in the whitelist.");
        whitelist[_address] = false;
        _removeAddressFromArray(_address, whitelistedAddresses);

        emit RemoveFromWhitelist(_address, block.timestamp);
    }

    function isWhitelisted(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function airdropNFT() external onlyOwner {
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            address recipient = whitelistedAddresses[i];
            uint256 tokenId = _nextTokenId++;
            _safeMint(recipient, tokenId);
        }
    }

    function editMintWindows(bool _publicMintOpen) external onlyOwner {
        publicMintOpen = _publicMintOpen;
    }

    function editMaxMintPerWallet(
        uint256 _publicMintMax
    ) external onlyOwner {
        maxMintPerWalletPublicMint = _publicMintMax;
    }

    function withdraw() public onlyOwner nonReentrant {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "ETH Balance is zero");

        payable(msg.sender).transfer(ethBalance);
    }



    // ============ 4.  Minting Functions  // ============

    function safeMint(address to) public payable nonReentrant {
        require(whitelist[to] != true, "Whitelisted address are eligible for airdrops and not public mint");
        require(publicMintOpen, "Public Mint Closed");
        require(
            mintedCount[msg.sender] < maxMintPerWalletPublicMint,
            "Max Mint per wallet reached"
        );
        require(totalSupply() < MAX_SUPPLY, "Can't mint anymore tokens, Mint sold out");

        uint256 tokenId = _nextTokenId++;
        mintedCount[msg.sender]++;
        _safeMint(to, tokenId);
    }


    // ============ 5.  Update Max Supply Functions  // ============
    function editMaxSupply(uint256 _supply) public onlyOwner {
        MAX_SUPPLY = _supply;
    }

    receive() external payable {}

    fallback() external payable {}


    // ============== 6.  NFT fliping  // ==============

    function setBotAddress(address _bot) external onlyOwner {
        bot = _bot;
    }

    function buyFlipNFT(address _collectionAddress, uint256 _tokenId, uint256 _price, string memory _metadata) external onlyBot nonReentrant {
        require(!isFlipNFTExisted(_collectionAddress, _tokenId), "NFT already exists");
        
        _withdrawByBot(_price);
        _addFlipNFT(_collectionAddress, _tokenId, _price, _metadata);

        emit buyNFT(_collectionAddress, _tokenId, _price, _metadata);
    }

    function sellFlipNFT(address _collectionAddress, uint256 _tokenId) external payable onlyBot nonReentrant {
        require(isFlipNFTExisted(_collectionAddress, _tokenId), "NFT does not exist");
        require(msg.value > 0, "You can't sell NFTs with zero price");

        _deleteFlipNFT(_collectionAddress, _tokenId);
        emit sellNFT(_collectionAddress, _tokenId);
    }

    function _addFlipNFT(address _collectionAddress, uint256 _tokenId, uint256 _price, string memory _metadata) internal {
        require(!isFlipNFTExisted(_collectionAddress, _tokenId), "NFT already exists");

        nfts.push(FlipNFT({
            collectionAddress: _collectionAddress,
            tokenId: _tokenId,
            price: _price,
            metadata: _metadata
        }));

        nftIndex[_collectionAddress][_tokenId] = nfts.length - 1;
        nftExists[_collectionAddress][_tokenId] = true;
    }

    function _deleteFlipNFT(address _collectionAddress, uint256 _tokenId) internal {
        require(isFlipNFTExisted(_collectionAddress, _tokenId), "NFT does not exist");

        uint256 index = nftIndex[_collectionAddress][_tokenId];
        uint256 lastIndex = nfts.length - 1;
        
        if (index != lastIndex) {
            FlipNFT storage lastNFT = nfts[lastIndex];
            nfts[index] = lastNFT;
            nftIndex[lastNFT.collectionAddress][lastNFT.tokenId] = index;
        }

        nfts.pop();
        delete nftIndex[_collectionAddress][_tokenId];
        delete nftExists[_collectionAddress][_tokenId];
    }

    function isFlipNFTExisted(address _collectionAddress, uint256 _tokenId) public view returns (bool) {
        return nftExists[_collectionAddress][_tokenId];
    }

    function getAllFlipNFTs() external view returns (FlipNFT[] memory) {
        return nfts;
    }

    function getTotalAssetsValue() external view returns (uint256) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < nfts.length; i++) {
            totalValue += nfts[i].price;
        }
        return totalValue;
    }

    function getFlipNFT(address _collectionAddress, uint256 _tokenId) external view returns (FlipNFT memory) {
        require(nftExists[_collectionAddress][_tokenId], "NFT does not exist");
        return nfts[nftIndex[_collectionAddress][_tokenId]];
    }

    function _withdrawByBot(uint256 _amount) internal {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > _amount, "Insufficient ETH balance to withdraw");        
        payable(bot).transfer(_amount);
    }


    // ============ 7.  Interact with Staking contract  // ============

    function setStakingContractAddress(address _stakingContractAddress) external onlyOwner {
        stakingContract = _stakingContractAddress;
    }

    function withdrawByStakingContract(address _receiver, uint256 _amount) external onlyStakingContract nonReentrant {
        require(address(this).balance > _amount, "Insufficient ETH balance to withdraw");
        payable(_receiver).transfer(_amount);
    }


    // ============   WETH related Functions  // ============

    function swapEthToWeth(uint256 _amount) external onlyStakingContract nonReentrant {
        require(address(this).balance > _amount, "Insufficient ETH balance to swap");
        weth.deposit{value: _amount}();
    }

    function swapWethToEth(uint256 _amount) external onlyStakingContract nonReentrant {
        require(weth.balanceOf(address(this)) >= _amount, "Insufficient WETH balance to swap");
        weth.withdraw(_amount);
    }

    function getWethBalance() external view returns (uint256) {
        return weth.balanceOf(address(this));
    }


    // ============   Other Functions  // ============

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

    // The following functions are overrides required by Solidity.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable, ERC721Pausable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override (ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override (ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }


    // ============ 9.  Modifier  // ============

    modifier onlyBot() {
        require(msg.sender == bot, "Not the Bot");
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Not the Staking Contract");
        _;
    }

    // ============ 10.  Events  // ============

    event buyNFT(address indexed collectionAddress, uint256 indexed tokenId, uint256 price, string metadata);
    event sellNFT(address indexed collectionAddress, uint256 indexed tokenId);
    event AddToWhitelist(address indexed user, uint256 timestamp);
    event RemoveFromWhitelist(address indexed user, uint256 timestamp);
}
