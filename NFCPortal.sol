// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract NFCReplicaToken is ERC20, ERC20Burnable, Ownable {
    constructor(
        string memory _name,
        string memory _symbol

    ) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

interface IMasterchef {
    function getUserFee(address account) external returns (uint256);
}

interface INFCReplicaToken {
    function mint(address _to, uint256 _amount) external;
    function burnFrom(address account, uint256 _amount) external;
}


contract NFCPortal is IERC721Receiver, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    INFCReplicaToken public immutable token;
    IERC721 public immutable nft;
    IERC20 public constant feeToken = IERC20(0x138408DB4173B48570f1BFb269326c63887483A7); // NFC Contract

    uint8 public exchangeFee = 100; // 100 = 100%
    address public exchangeWallet = 0xd1D629D2D6870Cc58A2c26615EAa83cC0303ad20;
    address public artistWallet = 0x0000000000000000000000000000000000000000;

    IMasterchef public constant masterchef = IMasterchef(0x2CDfF1c0cD3de197726E149c1aEaEF4b1A83Fc56); // NFC Masterchef

    uint256 public tradedCount = 0;
    uint256 public startTimestamp;

    mapping (uint256 => bool) public isTokenIDAuthorized;
    mapping (uint256 => bool) public isTokenIDAvailable;

    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet internal tokenIDsAvailable;

    bool public immutable isAllTokenIDsAuthorized;

    event ExchangeFee(address indexed user, uint8 exchangeFee);
    event ExchangeWallet(address indexed user, address exchangeWallet);
    event ArtistWallet(address indexed user, address artistWallet);
    event StartTimestamp(address indexed user, uint256 startTimestamp);
    event TokenIDsAuthorized(address indexed user, uint256[] tokenIDsAuthorized);

    constructor( 
        address _nft,
        string memory _replicaTokenName,
        string memory _replicaTokenSymbol,
        uint256 _startTimestamp,
        bool _isAllTokenIDsAuthorized
        ){

        require (_startTimestamp < block.timestamp + 30 days, "Should not start in more than 30 days from now");
        startTimestamp = _startTimestamp;

        nft = IERC721(_nft);
        address newToken = address(new NFCReplicaToken(_replicaTokenName, _replicaTokenSymbol));
        token = INFCReplicaToken(newToken);
        isAllTokenIDsAuthorized = _isAllTokenIDsAuthorized;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns(bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Get userFeeAmount
    function getUserFeeAmount(address _account) public returns (uint256) {
        return masterchef.getUserFee(_account);
    }

    // Get artistFee
    function getArtistFee() public view returns (uint8) {
        return 100 - exchangeFee ;
    }

    // Get tokenIds deposited
    function getArrayTokenIDsAvailable() external view returns (uint256[] memory) {
        return tokenIDsAvailable.values();
    }

    function depositNFTsForToken(uint256[] calldata _tokenIds) external nonReentrant {
        if(block.timestamp < startTimestamp){
            require (_msgSender() == owner(), "Portal not open for users");
        }

        uint256 userFeeAmount = getUserFeeAmount(_msgSender());
        uint256 nbTokenIds = _tokenIds.length;
        require(feeToken.allowance(_msgSender(), address(this)) >= userFeeAmount * nbTokenIds, "Fee Token allowance too low");
        require(nbTokenIds > 0 && nbTokenIds <= 50, "limited to 50 NFTs max per tx");

        for (uint256 i = 0; i < nbTokenIds; i++) {
            require(nft.ownerOf(_tokenIds[i]) == _msgSender(), "Invalid tokenId");
            require(isAllTokenIDsAuthorized || isTokenIDAuthorized[_tokenIds[i]] == true, "Non-authorized tokenID");
            nft.safeTransferFrom(_msgSender(), address(this), _tokenIds[i]);
            isTokenIDAvailable[_tokenIds[i]] = true;
            tokenIDsAvailable.add(_tokenIds[i]);
        }

        token.mint(_msgSender(), nbTokenIds * 10**18);

        if(userFeeAmount > 0 && exchangeWallet != address(0) && exchangeFee > 0){
            feeToken.safeTransferFrom(_msgSender(), exchangeWallet, (userFeeAmount * exchangeFee/100) * nbTokenIds);
        }

        uint8 artistFee = getArtistFee();
        if(userFeeAmount > 0 && artistWallet != address(0) && artistFee > 0){
            feeToken.safeTransferFrom(_msgSender(), artistWallet, (userFeeAmount * artistFee/100) * nbTokenIds);
        }

        tradedCount = tradedCount + nbTokenIds;
    }

    function burnTokenForNFTs(uint256[] calldata _tokenIds) external nonReentrant {
        if(block.timestamp < startTimestamp){
            require (_msgSender() == owner(), "Portal not open for users");
        }

        uint256 userFeeAmount = getUserFeeAmount(_msgSender());
        uint256 nbTokenIds = _tokenIds.length;
        require(feeToken.allowance(_msgSender(), address(this)) >= userFeeAmount * nbTokenIds, "Fee Token allowance too low");
        require(nbTokenIds > 0 && nbTokenIds <= 50, "limited to 50 NFTs max per tx");

        for (uint256 i = 0; i < nbTokenIds; i++) {
            require(nft.ownerOf(_tokenIds[i]) == address(this), "Invalid tokenId");
            require(isAllTokenIDsAuthorized || isTokenIDAuthorized[_tokenIds[i]] == true, "Non-authorized tokenID");
            require(isTokenIDAvailable[_tokenIds[i]] == true, "Not available tokenID for swap");
            nft.safeTransferFrom(address(this), _msgSender(), _tokenIds[i]);
            isTokenIDAvailable[_tokenIds[i]] = false;
            tokenIDsAvailable.remove(_tokenIds[i]);
        }

        token.burnFrom(_msgSender(), nbTokenIds * 10**18);

        if(userFeeAmount > 0 && exchangeWallet != address(0) && exchangeFee > 0){
            feeToken.safeTransferFrom(_msgSender(), exchangeWallet, (userFeeAmount * exchangeFee/100) * nbTokenIds);
        }

        uint8 artistFee = getArtistFee();
        if(userFeeAmount > 0 && artistWallet != address(0) && artistFee > 0){
            feeToken.safeTransferFrom(_msgSender(), artistWallet, (userFeeAmount * artistFee/100) * nbTokenIds);
        }

        tradedCount = tradedCount + nbTokenIds;
    }


    function depositNFTsForNFTs(uint256[] calldata _tokenIds, uint256[] calldata _tokenIdsWanted) external nonReentrant {
        if(block.timestamp < startTimestamp){
            require (_msgSender() == owner(), "Portal not open for users");
        }

        uint256 userFeeAmount = getUserFeeAmount(_msgSender());
        uint256 nbTokenIds = _tokenIds.length;
        uint256 nbTokenIdsWanted = _tokenIdsWanted.length;

        require(nbTokenIds == nbTokenIdsWanted, "Need same NFTs amount");
        require(feeToken.allowance(_msgSender(), address(this)) >= userFeeAmount * nbTokenIds, "Fee Token allowance too low");
        require(nbTokenIds > 0 && nbTokenIds <= 25, "limited to 25 NFTs max per tx");

        for (uint256 i = 0; i < nbTokenIds; i++) {
            require(nft.ownerOf(_tokenIds[i]) == _msgSender(), "Invalid tokenId");
            require(isAllTokenIDsAuthorized || isTokenIDAuthorized[_tokenIds[i]] == true, "Non-authorized tokenID");
            nft.safeTransferFrom(_msgSender(), address(this), _tokenIds[i]);
            isTokenIDAvailable[_tokenIds[i]] = true;
            tokenIDsAvailable.add(_tokenIds[i]);
        }

        for (uint256 i = 0; i < nbTokenIdsWanted; i++) {
            require(nft.ownerOf(_tokenIdsWanted[i]) == address(this), "Invalid tokenId");
            require(isAllTokenIDsAuthorized || isTokenIDAuthorized[_tokenIdsWanted[i]] == true, "Non-authorized tokenID");
            require(isTokenIDAvailable[_tokenIdsWanted[i]] == true, "Not available tokenID for swap");
            nft.safeTransferFrom(address(this), _msgSender(), _tokenIdsWanted[i]);
            isTokenIDAvailable[_tokenIdsWanted[i]] = false;
            tokenIDsAvailable.remove(_tokenIdsWanted[i]);
        }

        if(userFeeAmount > 0 && exchangeWallet != address(0) && exchangeFee > 0){
            feeToken.safeTransferFrom(_msgSender(), exchangeWallet, (userFeeAmount * exchangeFee/100) * nbTokenIds);
        }

        uint8 artistFee = getArtistFee();
        if(userFeeAmount > 0 && artistWallet != address(0) && artistFee > 0){
            feeToken.safeTransferFrom(_msgSender(), artistWallet, (userFeeAmount * artistFee/100) * nbTokenIds);
        }

        tradedCount = tradedCount + nbTokenIds;
    }

    function setExchangeFee(uint8 _exchangeFee) external onlyOwner {
        require(_exchangeFee <= 100, "exchangeFee too high");
        exchangeFee = _exchangeFee;
        emit ExchangeFee(msg.sender, _exchangeFee);
    }

    function setExchangeWallet(address _exchangeWallet) external onlyOwner {
        exchangeWallet = _exchangeWallet;
        emit ExchangeWallet(msg.sender, _exchangeWallet);
    }

    function setArtistWallet(address _artistWallet) external onlyOwner {
        artistWallet = _artistWallet;
        emit ArtistWallet(msg.sender, _artistWallet);
    }

    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        require (block.timestamp < startTimestamp, "already started");
        require (_startTimestamp < block.timestamp + 30 days, "Should not start in more than 30 days from now");

        startTimestamp = _startTimestamp;
        emit StartTimestamp(msg.sender, _startTimestamp);
    }

    function addTokenIDsAuthorized(uint256[] memory _tokenIDsAuthorized) external onlyOwner {
        require(isAllTokenIDsAuthorized == false, "All tokenIds are Authorized");
        for (uint256 i = 0; i < _tokenIDsAuthorized.length; i++) {
            isTokenIDAuthorized[_tokenIDsAuthorized[i]] = true;
        }
        emit TokenIDsAuthorized(msg.sender, _tokenIDsAuthorized);
    }

    //In case some users send directly NFTs to this contract, we will be able to withdraw only those ones
    function withdrawNFTsSentByError(address _nftContract, uint256[] calldata _tokenIds) external onlyOwner {
        uint256 nbTokenIds = _tokenIds.length;
        require(nbTokenIds > 0 && nbTokenIds <= 50, "limited to 50 NFTs max per tx");

        if(_nftContract == address(nft)){
            for (uint256 i = 0; i < nbTokenIds; i++) {
                require(nft.ownerOf(_tokenIds[i]) == address(this), "Invalid tokenId");
                require(isTokenIDAvailable[_tokenIds[i]] == false, "Only tokensIds sent by errors can be withdrawn");
                nft.safeTransferFrom(address(this), owner(), _tokenIds[i]);
            }
        }else{
            for (uint256 i = 0; i < nbTokenIds; i++) {
                require(IERC721(_nftContract).ownerOf(_tokenIds[i]) == address(this), "Invalid tokenId");
                IERC721(_nftContract).safeTransferFrom(address(this), owner(), _tokenIds[i]);
            }            
        }
    }

    //In case some users send directly Tokens to this contract
    function withdrawTokensSentByError(address _tokenContract) external onlyOwner {
        IERC20(_tokenContract).safeTransfer(owner(), IERC20(_tokenContract).balanceOf(address(this)));
    }

}