// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BadgerBotPool is
    ERC721,
    ERC721Enumerable,
    ERC721Pausable,
    ERC721Burnable,
    ReentrancyGuard
{
    // ============ 1.  Property Variables  // ============

    uint256 private _nextTokenId = 1;
    uint256 public MINT_PRICE = 0 ether;
    uint256 public MAX_SUPPLY = 5;

    address public owner;

    bool public publicMintOpen = false;

    mapping(address => bool) public whitelist;
    address[] public whitelistedAddresses;

    uint256 public maxMintPerWalletPublicMint = 1;

    mapping(address => uint256) public mintedCount;

    // ============ 2.  Lifecycle Methods  // ============
    constructor() ERC721("Badger Bot Pool", "BADGER") {
        owner = msg.sender;

        whitelist[address(0x297122b6514a9A857830ECcC6C41F1803963e516)] = true;
        whitelist[address(0xC95449734dDa7ac6d494a1077Ca7f1773be4F38D)] = true;
        whitelist[address(0x9F7496082F6bB1D27B84BE9BB10A423A1A4d9A1F)] = true;
        whitelist[address(0x3d8e88d73297157C6125E76ec6f92BABAE2eC949)] = true;
        whitelist[address(0xda6Fb0F91e321bB66cDE6eD92803A2BD8f3e8ac6)] = true;

        whitelistedAddresses.push(address(0x297122b6514a9A857830ECcC6C41F1803963e516));
        whitelistedAddresses.push(address(0xC95449734dDa7ac6d494a1077Ca7f1773be4F38D));
        whitelistedAddresses.push(address(0x9F7496082F6bB1D27B84BE9BB10A423A1A4d9A1F));
        whitelistedAddresses.push(address(0x3d8e88d73297157C6125E76ec6f92BABAE2eC949));
        whitelistedAddresses.push(address(0xda6Fb0F91e321bB66cDE6eD92803A2BD8f3e8ac6));
    }

    string public uri = "ipfs://bafkreibuoqdbhfje3wwwb2xjp2j6uw4tlcqks6m7jycf7b2dosrtp3n7i4";

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function isWhitelisted(address _address) external view returns (bool) {
        return whitelist[_address];
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return uri;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://bafkreibuoqdbhfje3wwwb2xjp2j6uw4tlcqks6m7jycf7b2dosrtp3n7i4";
    }


    function setMintFee(uint256 _mintFee) external onlyOwner {
        MINT_PRICE = _mintFee;
    }

    function addToWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            whitelist[addr] = true;
            if (!isAddressInArray(addr, whitelistedAddresses)) {
                whitelistedAddresses.push(addr);
            }
        }
    }

    function removeFromWhitelist(address[] memory _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            whitelist[addr] = false;
            removeAddressFromArray(addr, whitelistedAddresses);
        }
    }

    function airdropNFT() external onlyOwner {
        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            address recipient = whitelistedAddresses[i];
            uint256 tokenId = _nextTokenId++;
            _safeMint(recipient, tokenId);
        }
    }

    function isAddressInArray(address _address, address[] memory _array) internal pure returns (bool) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function removeAddressFromArray(address _address, address[] storage _array) internal {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _address) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
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
        uint256 balance = address(this).balance;
        require(balance > 0, "Balance is zero");

        payable(owner).transfer(balance);
    }

    // ============ 3.  Pausable Functions  // ============
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
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

    // receive() external payable {}

    // fallback() external payable {}

    // The following functions are overrides required by Solidity.
    // ============ 6.  Other Functions  // ============
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
}
