// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BuyChestTestContract.sol";

/**
 * @title ChestBuyTestV2
 * @dev V2 of the ChestBuyTest contract.
 * Adds verification helper and auto-increment tokenId logic.
 */
contract ChestBuyTestV2 is ChestBuyTest {
    
    // --- New State Variables ---
    // Tracks the next available token ID for auto-increment minting
    uint256 public nextTokenId;

    // --- New Functions ---

    /**
     * @dev Returns the version of the contract.
     */
    function version() external pure returns (string memory) {
        return "V2";
    }

    /**
     * @dev Verifies that a mint request is valid and signed by the owner.
     * Does not check if UID was already processed (stateless check).
     */
    function verify(MintRequest calldata _req, bytes calldata _signature) external view returns (bool, address) {
        // Basic validation checks
        if (_req.validityStartTimestamp > block.timestamp) return (false, address(0));
        if (_req.validityEndTimestamp < block.timestamp) return (false, address(0));
        if (_req.quantity == 0) return (false, address(0));
        
        // Recover signer
        address signer = _recoverAddress(_req, _signature);
        bool isValid = (signer == owner());
        
        return (isValid, signer);
    }

    /**
     * @dev Returns the next token ID that will be minted if using type(uint256).max
     */
    function getNextTokenId() external view returns (uint256) {
        return nextTokenId;
    }

    /**
     * @dev Override mintWithSignature to support auto-increment token IDs.
     */
    function mintWithSignature(
        MintRequest calldata _req,
        bytes calldata _signature
    ) external payable virtual override nonReentrant {
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

        // 4. Handle Payment
        if (_req.pricePerToken > 0) {
            uint256 totalPrice = _req.quantity * _req.pricePerToken;
            if (_req.currency == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                require(msg.value == totalPrice, "Incorrect ETH amount sent");
                (bool success, ) = owner().call{value: msg.value}("");
                require(success, "Failed to transfer ETH to owner");
            } else {
                 revert("Only native currency supported currently");
            }
        }

        // 5. Determine Token ID
        uint256 tokenIdToMint;
        if (_req.tokenId == type(uint256).max) {
            tokenIdToMint = nextTokenId;
            nextTokenId += 1;
        } else {
            tokenIdToMint = _req.tokenId;
        }

        // 6. Mint
        if (bytes(_req.uri).length > 0) {
            _setURI(tokenIdToMint, _req.uri);
        }
        _mint(_req.to, tokenIdToMint, _req.quantity, "");

        // Emit event with the ACTUAL tokenId minted
        emit TokensMintedWithSignature(signer, _req.to, tokenIdToMint, _req);
    }
}
