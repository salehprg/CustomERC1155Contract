// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// OpenZeppelin v5 Imports
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract ChestBuyTest_721 is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    ERC2981Upgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;

    // --- State Variables ---

    string public contractURI; // OpenSea collection metadata URI

    // Mapping to track used mint request UIDs to prevent replay attacks
    mapping(bytes32 => bool) public processedUIDs;

    uint256 public nextTokenId;

    // Typehash for EIP712
    bytes32 private constant MINT_REQUEST_TYPEHASH =
        keccak256(
            "MintRequest(address to,uint256 tokenId,string uri,uint256 pricePerToken,address currency,uint128 validityStartTimestamp,uint128 validityEndTimestamp,bytes32 uid)"
        );

    struct MintRequest {
        address to;
        uint256 tokenId;
        string uri;
        uint256 pricePerToken;
        address currency;
        uint128 validityStartTimestamp;
        uint128 validityEndTimestamp;
        bytes32 uid;
    }

    event TokensMintedWithSignature(
        address indexed signer,
        address indexed to,
        uint256 indexed tokenId,
        MintRequest req
    );

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

        __ERC721_init(_name, _symbol);
        __ERC721URIStorage_init();
        __Ownable_init(_defaultAdmin); // Explicitly pass initial owner for OZ v5
        __ERC2981_init();
        __EIP712_init("ChestBuyTest", "1");
        __ReentrancyGuard_init();

        contractURI = _contractURI;

        // Set default royalty
        _setDefaultRoyalty(_royaltyRecipient, _royaltyBps);
    }

    function verify(
        MintRequest calldata _req,
        bytes calldata _signature
    ) external view returns (bool, address) {
        // Basic validation checks
        if (_req.validityStartTimestamp > block.timestamp)
            return (false, address(0));
        if (_req.validityEndTimestamp < block.timestamp)
            return (false, address(0));

        // Recover signer
        address signer = _recoverAddress(_req, _signature);
        bool isValid = (signer == owner());

        return (isValid, signer);
    }
    // --- Core Logic ---

    function nextTokenIdToMint() external view returns (uint256) {
        return nextTokenId;
    }

    /**
     * @dev Mint ERC721 tokens via EIP-712 signature.
     * - If `_req.tokenId == type(uint256).max`, mints `_req.quantity` sequential tokenIds starting at `nextTokenId`.
     * - Otherwise requires `_req.quantity == 1` and mints exactly `_req.tokenId`.
     */
    function mintWithSignature(
        MintRequest calldata _req,
        bytes calldata _signature
    ) external payable virtual nonReentrant {
        // 1. Validation
        require(
            _req.validityStartTimestamp <= block.timestamp,
            "Request not yet valid"
        );
        require(
            _req.validityEndTimestamp >= block.timestamp,
            "Request expired"
        );
        require(!processedUIDs[_req.uid], "Request already processed");

        // 2. Verify Signature
        address signer = _recoverAddress(_req, _signature);
        require(signer == owner(), "Invalid signature");

        // 3. Mark UID as processed
        processedUIDs[_req.uid] = true;

        // 4. Handle Payment
        if (_req.pricePerToken > 0) {
            if (
                _req.currency ==
                address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
            ) {
                require(
                    msg.value == _req.pricePerToken,
                    "Incorrect ETH amount sent"
                );
                (bool success, ) = owner().call{value: msg.value}("");
                require(success, "Failed to transfer ETH to owner");
            } else {
                revert("Only native currency supported currently");
            }
        }

        // 5. Determine tokenIds to mint
        uint256 startTokenId;
        if (_req.tokenId == type(uint256).max) {
            startTokenId = nextTokenId;
            unchecked {
                nextTokenId += 1;
            }
        } else {
            startTokenId = _req.tokenId;
        }

        _safeMint(_req.to, startTokenId);
        if (bytes(_req.uri).length > 0) {
            _setTokenURI(startTokenId, _req.uri);
        }
        emit TokensMintedWithSignature(signer, _req.to, startTokenId, _req);
    }

    // --- EIP-712 Helpers ---

    function _hashRequest(
        MintRequest calldata _req
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    MINT_REQUEST_TYPEHASH,
                    _req.to,
                    _req.tokenId,
                    keccak256(bytes(_req.uri)),
                    _req.pricePerToken,
                    _req.currency,
                    _req.validityStartTimestamp,
                    _req.validityEndTimestamp,
                    _req.uid
                )
            );
    }

    function _recoverAddress(
        MintRequest calldata _req,
        bytes calldata _signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(_hashRequest(_req));
        return ECDSA.recover(digest, _signature);
    }

    // --- Admin Functions ---

    function setURI(
        uint256 _tokenId,
        string memory _tokenURI
    ) external onlyOwner {
        _setTokenURI(_tokenId, _tokenURI);
    }

    // Sets the contract-level metadata URI (for OpenSea)
    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    function setRoyaltyInfo(
        address _receiver,
        uint96 _feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    // --- Internal Overrides ---

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // The following functions are overrides required by Solidity for OZ v5.

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721Upgradeable,
            ERC721URIStorageUpgradeable,
            ERC2981Upgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
