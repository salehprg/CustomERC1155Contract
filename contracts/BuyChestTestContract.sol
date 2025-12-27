// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// OpenZeppelin v5 Imports
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title ChestBuyTest
 * @dev Simple Upgradeable ERC1155 with Signature Minting using pure OpenZeppelin v5.
 * 
 * Note: This code is designed for OpenZeppelin Contracts Upgradeable v5.x.
 * If you are compiling locally with v4.x, you will need to update your dependencies:
 * npm install @openzeppelin/contracts-upgradeable@5
 */
contract ChestBuyTest is 
    Initializable, 
    ERC1155Upgradeable, 
    ERC1155URIStorageUpgradeable,
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable, 
    ERC2981Upgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    using ECDSAUpgradeable for bytes32;

    // --- State Variables ---

    string public name;
    string public symbol;
    string public contractURI; // OpenSea collection metadata URI
    
    // Mapping to track used mint request UIDs to prevent replay attacks
    mapping(bytes32 => bool) public processedUIDs;

    // Typehash for EIP712
    bytes32 private constant MINT_REQUEST_TYPEHASH = keccak256(
        "MintRequest(address to,uint256 tokenId,string uri,uint256 quantity,uint256 pricePerToken,address currency,uint128 validityStartTimestamp,uint128 validityEndTimestamp,bytes32 uid)"
    );

    struct MintRequest {
        address to;
        uint256 tokenId;
        string uri;
        uint256 quantity;
        uint256 pricePerToken;
        address currency;
        uint128 validityStartTimestamp;
        uint128 validityEndTimestamp;
        bytes32 uid;
    }

    event TokensMintedWithSignature(address indexed signer, address indexed to, uint256 indexed tokenId, MintRequest req);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address _royaltyRecipient,
        uint96 _royaltyBps
    ) external initializer {
        require(_defaultAdmin != address(0), "Admin cannot be zero address");
        
        __ERC1155_init("");
        __ERC1155URIStorage_init();
        __ERC1155Supply_init();
        __Ownable_init(_defaultAdmin); // Explicitly pass initial owner for OZ v5
        __ERC2981_init();
        __EIP712_init("ChestBuyTest", "1");
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        name = _name;
        symbol = _symbol;
        contractURI = _contractURI;
        
        // Set default royalty
        _setDefaultRoyalty(_royaltyRecipient, _royaltyBps);
    }

    // --- Core Logic ---

    /**
     * @dev Mint tokens using a signature provided by the owner (or authorized signer).
     */
    function mintWithSignature(
        MintRequest calldata _req,
        bytes calldata _signature
    ) external payable virtual nonReentrant {
        // 1. Validation
        require(_req.validityStartTimestamp <= block.timestamp, "Request not yet valid");
        require(_req.validityEndTimestamp >= block.timestamp, "Request expired");
        require(_req.quantity > 0, "Quantity must be > 0");
        require(!processedUIDs[_req.uid], "Request already processed");

        // 2. Verify Signature
        address signer = _recoverAddress(_req, _signature);
        require(signer == owner(), "Invalid signature");

        // 3. Mark UID as processed
        processedUIDs[_req.uid] = true;
        
        // 4. Handle Payment (Native ETH only for simplicity, add ERC20 support if needed)
        if (_req.pricePerToken > 0) {
            uint256 totalPrice = _req.quantity * _req.pricePerToken;
            if (_req.currency == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                require(msg.value == totalPrice, "Incorrect ETH amount sent");
                
                (bool success, ) = owner().call{value: msg.value}("");
                require(success, "Failed to transfer ETH to owner");
            } else {
                 // Logic for ERC20 would go here if needed (safeTransferFrom)
                 revert("Only native currency supported currently");
            }
        }

        // 5. Mint
        if (bytes(_req.uri).length > 0) {
            _setURI(_req.tokenId, _req.uri);
        }
        _mint(_req.to, _req.tokenId, _req.quantity, "");

        emit TokensMintedWithSignature(signer, _req.to, _req.tokenId, _req);
    }

    // --- EIP-712 Helpers ---

    function _hashRequest(MintRequest calldata _req) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            MINT_REQUEST_TYPEHASH,
            _req.to,
            _req.tokenId,
            keccak256(bytes(_req.uri)),
            _req.quantity,
            _req.pricePerToken,
            _req.currency,
            _req.validityStartTimestamp,
            _req.validityEndTimestamp,
            _req.uid
        ));
    }

    function _recoverAddress(MintRequest calldata _req, bytes calldata _signature) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(_hashRequest(_req));
        return ECDSAUpgradeable.recover(digest, _signature);
    }

    // --- Admin Functions ---

    function setURI(uint256 _tokenId, string memory _tokenURI) external onlyOwner {
        _setURI(_tokenId, _tokenURI);
    }
    
    // Sets the contract-level metadata URI (for OpenSea)
    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    function setRoyaltyInfo(address _receiver, uint96 _feeNumerator) external onlyOwner {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    // --- Internal Overrides ---

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // The following functions are overrides required by Solidity for OZ v5.

    // Replaces _beforeTokenTransfer in OZ v5
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }

    function uri(uint256 tokenId) public view override(ERC1155Upgradeable, ERC1155URIStorageUpgradeable) returns (string memory) {
        return super.uri(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
