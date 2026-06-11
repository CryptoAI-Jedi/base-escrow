// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IEscrowMarket — external interface of the Base Escrow marketplace
/// @notice Consumed by the web app, the Ponder indexer, and resolver tooling.
interface IEscrowMarket {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum EscrowStatus {
        None,
        Funded,
        Disputed,
        Released,
        Refunded
    }

    struct Listing {
        address seller;
        address token; // address(0) = native ETH
        uint96 price;
        bytes32 category; // keccak256 of canonical category slug
        string metadataCID; // IPFS CID: title, description, images
        bool active;
    }

    struct Escrow {
        uint256 listingId;
        address buyer;
        address seller;
        address token;
        uint96 amount; // price snapshot at purchase
        uint96 feeAmount; // fee snapshot at purchase (taken from amount on release)
        EscrowStatus status;
        uint64 releaseDeadline; // created + releaseWindow
        uint64 sellerResponseDeadline; // set when dispute opens
        string evidenceCID; // latest evidence commitment (IPFS CID)
        address disputedBy;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address token,
        uint96 price,
        bytes32 indexed category,
        string metadataCID
    );
    event ListingUpdated(uint256 indexed listingId, uint96 price, string metadataCID);
    event ListingCancelled(uint256 indexed listingId);

    event EscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        address token,
        uint96 amount,
        uint96 feeAmount,
        uint64 releaseDeadline
    );
    event Released(uint256 indexed escrowId, address indexed by, uint96 amount, uint96 fee);
    event Refunded(uint256 indexed escrowId, address indexed by, uint96 amount);
    event DisputeOpened(
        uint256 indexed escrowId, address indexed by, string evidenceCID, uint64 sellerResponseDeadline
    );
    event EvidenceSubmitted(uint256 indexed escrowId, address indexed by, string cid);
    event Resolved(uint256 indexed escrowId, uint8 action, bytes32 reasonCode);
    event WithdrawalQueued(address indexed to, address token, uint256 amount);

    event FeeUpdated(uint16 bps);
    event TreasuryUpdated(address treasury);
    event ResolverUpdated(address resolver);
    event TokenAllowed(address token, bool allowed);
    event WindowsUpdated(uint64 releaseWindow, uint64 sellerResponseWindow);

    // ---------------------------------------------------------------------
    // Marketplace
    // ---------------------------------------------------------------------

    function createListing(address token, uint96 price, bytes32 category, string calldata metadataCID)
        external
        returns (uint256 listingId);

    function updateListing(uint256 listingId, uint96 price, string calldata metadataCID) external;

    function cancelListing(uint256 listingId) external;

    /// @notice Buy a native-ETH listing: atomically creates AND funds the escrow.
    function buy(uint256 listingId) external payable returns (uint256 escrowId);

    /// @notice Buy an ERC-20 listing (requires prior approval of the listing price).
    function buyERC20(uint256 listingId) external returns (uint256 escrowId);

    // ---------------------------------------------------------------------
    // Escrow lifecycle
    // ---------------------------------------------------------------------

    function release(uint256 escrowId) external;

    function openDispute(uint256 escrowId, string calldata evidenceCID) external;

    function submitEvidence(uint256 escrowId, string calldata cid) external;

    function resolveRelease(uint256 escrowId, bytes32 reasonCode) external;

    function resolveRefund(uint256 escrowId, bytes32 reasonCode) external;

    function withdraw(address token) external;

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getListing(uint256 listingId) external view returns (Listing memory);

    function getEscrow(uint256 escrowId) external view returns (Escrow memory);

    function nextListingId() external view returns (uint256);

    function nextEscrowId() external view returns (uint256);

    function withdrawable(address account, address token) external view returns (uint256);

    function allowedTokens(address token) external view returns (bool);

    function resolver() external view returns (address);

    function treasury() external view returns (address);

    function feeBps() external view returns (uint16);

    function releaseWindow() external view returns (uint64);

    function sellerResponseWindow() external view returns (uint64);
}
