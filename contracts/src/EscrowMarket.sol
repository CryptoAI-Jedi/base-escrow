// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEscrowMarket} from "./interfaces/IEscrowMarket.sol";
import "./libraries/Errors.sol";

/// @title EscrowMarket — multi-escrow marketplace on Base
/// @notice Monolithic marketplace: sellers create listings, buyers purchase via
///         atomically-funded escrows, disputes are resolved by an off-chain
///         resolver (Chainlink CRE submits the resolution transactions).
/// @dev Design properties:
///      - Funding is atomic with purchase; there is no unfunded escrow state.
///      - The resolver can ONLY move an escrow's funds to that escrow's buyer
///        or seller, never to a third party.
///      - Payouts fall back to pull-payment (`withdraw`) when a direct
///        transfer fails, so a reverting recipient can never block resolution.
///      - `pause` blocks new listings and purchases only; release, refund,
///        dispute, and withdrawal paths are never pausable.
contract EscrowMarket is IEscrowMarket, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint16 public constant MAX_FEE_BPS = 500; // hard cap: 5%
    uint16 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev `action` values for the `Resolved` event.
    uint8 internal constant ACTION_RELEASE = 1;
    uint8 internal constant ACTION_REFUND = 2;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    mapping(uint256 => Listing) internal _listings;
    mapping(uint256 => Escrow) internal _escrows;
    uint256 public nextListingId = 1;
    uint256 public nextEscrowId = 1;

    mapping(address => bool) public allowedTokens;
    mapping(address => mapping(address => uint256)) public withdrawable; // account => token => amount

    address public resolver;
    address public treasury;
    uint16 public feeBps;
    uint64 public releaseWindow;
    uint64 public sellerResponseWindow;

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(
        address owner_,
        address resolver_,
        address treasury_,
        uint64 releaseWindow_,
        uint64 sellerResponseWindow_
    ) Ownable(owner_) {
        if (resolver_ == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (releaseWindow_ == 0 || sellerResponseWindow_ == 0) revert ZeroWindow();
        resolver = resolver_;
        treasury = treasury_;
        releaseWindow = releaseWindow_;
        sellerResponseWindow = sellerResponseWindow_;
        emit ResolverUpdated(resolver_);
        emit TreasuryUpdated(treasury_);
        emit WindowsUpdated(releaseWindow_, sellerResponseWindow_);
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyResolver() {
        if (msg.sender != resolver) revert NotResolver(msg.sender);
        _;
    }

    // ---------------------------------------------------------------------
    // Marketplace: listings
    // ---------------------------------------------------------------------

    /// @inheritdoc IEscrowMarket
    function createListing(address token, uint96 price, bytes32 category, string calldata metadataCID)
        external
        whenNotPaused
        returns (uint256 listingId)
    {
        if (price == 0) revert ZeroPrice();
        if (token != address(0) && !allowedTokens[token]) revert TokenNotAllowed(token);

        listingId = nextListingId++;
        _listings[listingId] = Listing({
            seller: msg.sender,
            token: token,
            price: price,
            category: category,
            metadataCID: metadataCID,
            active: true
        });

        emit ListingCreated(listingId, msg.sender, token, price, category, metadataCID);
    }

    /// @inheritdoc IEscrowMarket
    /// @dev Price changes never affect open escrows: `buy` snapshots the price.
    function updateListing(uint256 listingId, uint96 price, string calldata metadataCID) external {
        Listing storage listing = _requireActiveListing(listingId);
        if (msg.sender != listing.seller) revert NotSeller(msg.sender);
        if (price == 0) revert ZeroPrice();

        listing.price = price;
        listing.metadataCID = metadataCID;

        emit ListingUpdated(listingId, price, metadataCID);
    }

    /// @inheritdoc IEscrowMarket
    function cancelListing(uint256 listingId) external {
        Listing storage listing = _requireActiveListing(listingId);
        if (msg.sender != listing.seller) revert NotSeller(msg.sender);

        listing.active = false;

        emit ListingCancelled(listingId);
    }

    // ---------------------------------------------------------------------
    // Marketplace: purchase (atomic create + fund)
    // ---------------------------------------------------------------------

    /// @inheritdoc IEscrowMarket
    function buy(uint256 listingId) external payable whenNotPaused nonReentrant returns (uint256 escrowId) {
        Listing storage listing = _requireActiveListing(listingId);
        if (listing.token != address(0)) revert TokenNotAllowed(listing.token);
        if (msg.value != listing.price) revert WrongValue(listing.price, msg.value);

        escrowId = _createEscrow(listingId, listing);
    }

    /// @inheritdoc IEscrowMarket
    function buyERC20(uint256 listingId) external whenNotPaused nonReentrant returns (uint256 escrowId) {
        Listing storage listing = _requireActiveListing(listingId);
        address token = listing.token;
        if (token == address(0)) revert TokenNotAllowed(token);

        // Balance-delta check rejects fee-on-transfer behavior even if such a
        // token were ever whitelisted by mistake.
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), listing.price);
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (received != listing.price) revert UnexpectedTransferAmount(listing.price, received);

        escrowId = _createEscrow(listingId, listing);
    }

    function _createEscrow(uint256 listingId, Listing storage listing) internal returns (uint256 escrowId) {
        if (msg.sender == listing.seller) revert SelfPurchase();

        uint96 amount = listing.price;
        uint96 feeAmount = uint96((uint256(amount) * feeBps) / BPS_DENOMINATOR);
        uint64 deadline = uint64(block.timestamp) + releaseWindow;

        escrowId = nextEscrowId++;
        _escrows[escrowId] = Escrow({
            listingId: listingId,
            buyer: msg.sender,
            seller: listing.seller,
            token: listing.token,
            amount: amount,
            feeAmount: feeAmount,
            status: EscrowStatus.Funded,
            releaseDeadline: deadline,
            sellerResponseDeadline: 0,
            evidenceCID: "",
            disputedBy: address(0)
        });

        emit EscrowCreated(
            escrowId, listingId, msg.sender, listing.seller, listing.token, amount, feeAmount, deadline
        );
    }

    // ---------------------------------------------------------------------
    // Escrow lifecycle
    // ---------------------------------------------------------------------

    /// @inheritdoc IEscrowMarket
    /// @dev Callable by the buyer in Funded (happy path) or Disputed (concede).
    function release(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = _requireEscrow(escrowId);
        if (msg.sender != escrow.buyer) revert NotBuyer(msg.sender);
        _requireOpen(escrowId, escrow);

        _doRelease(escrowId, escrow);
    }

    /// @inheritdoc IEscrowMarket
    /// @dev Either party may dispute, but only strictly before the release
    ///      deadline — so a dispute and an auto-release timeout can never both
    ///      be valid at the same timestamp.
    function openDispute(uint256 escrowId, string calldata evidenceCID) external {
        Escrow storage escrow = _requireEscrow(escrowId);
        _requireParty(escrow);
        if (escrow.status != EscrowStatus.Funded) revert InvalidStatus(escrowId, uint8(escrow.status));
        if (block.timestamp >= escrow.releaseDeadline) revert PastDeadline(escrow.releaseDeadline);

        uint64 responseDeadline = uint64(block.timestamp) + sellerResponseWindow;
        escrow.status = EscrowStatus.Disputed;
        escrow.sellerResponseDeadline = responseDeadline;
        escrow.evidenceCID = evidenceCID;
        escrow.disputedBy = msg.sender;

        emit DisputeOpened(escrowId, msg.sender, evidenceCID, responseDeadline);
    }

    /// @inheritdoc IEscrowMarket
    /// @dev Latest CID is stored on-chain; the full evidence history lives in
    ///      `EvidenceSubmitted` events (indexed off-chain).
    function submitEvidence(uint256 escrowId, string calldata cid) external {
        Escrow storage escrow = _requireEscrow(escrowId);
        _requireParty(escrow);
        if (escrow.status != EscrowStatus.Disputed) revert InvalidStatus(escrowId, uint8(escrow.status));

        escrow.evidenceCID = cid;

        emit EvidenceSubmitted(escrowId, msg.sender, cid);
    }

    /// @inheritdoc IEscrowMarket
    /// @dev Resolver path: Disputed (policy decision) or Funded past the
    ///      release deadline (AUTO_RELEASE_TIMEOUT).
    function resolveRelease(uint256 escrowId, bytes32 reasonCode) external onlyResolver nonReentrant {
        Escrow storage escrow = _requireEscrow(escrowId);
        if (escrow.status == EscrowStatus.Funded) {
            if (block.timestamp <= escrow.releaseDeadline) {
                revert DeadlineNotReached(escrow.releaseDeadline);
            }
        } else if (escrow.status != EscrowStatus.Disputed) {
            revert InvalidStatus(escrowId, uint8(escrow.status));
        }

        emit Resolved(escrowId, ACTION_RELEASE, reasonCode);
        _doRelease(escrowId, escrow);
    }

    /// @inheritdoc IEscrowMarket
    function resolveRefund(uint256 escrowId, bytes32 reasonCode) external onlyResolver nonReentrant {
        Escrow storage escrow = _requireEscrow(escrowId);
        if (escrow.status != EscrowStatus.Disputed) revert InvalidStatus(escrowId, uint8(escrow.status));

        escrow.status = EscrowStatus.Refunded;

        emit Resolved(escrowId, ACTION_REFUND, reasonCode);
        emit Refunded(escrowId, msg.sender, escrow.amount);

        // Refund returns the full amount (fee included) to the buyer.
        _payout(escrow.buyer, escrow.token, escrow.amount);
    }

    function _doRelease(uint256 escrowId, Escrow storage escrow) internal {
        escrow.status = EscrowStatus.Released;

        uint96 fee = escrow.feeAmount;
        uint96 sellerAmount = escrow.amount - fee;

        emit Released(escrowId, msg.sender, sellerAmount, fee);

        _payout(escrow.seller, escrow.token, sellerAmount);
        if (fee > 0) _payout(treasury, escrow.token, fee);
    }

    /// @inheritdoc IEscrowMarket
    function withdraw(address token) external nonReentrant {
        uint256 amount = withdrawable[msg.sender][token];
        if (amount == 0) revert NothingToWithdraw();

        withdrawable[msg.sender][token] = 0;

        if (token == address(0)) {
            (bool ok,) = msg.sender.call{value: amount}("");
            if (!ok) revert NativeTransferFailed(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    // ---------------------------------------------------------------------
    // Payouts: direct transfer with pull-payment fallback
    // ---------------------------------------------------------------------

    /// @dev Escrow state is always terminal before this runs (CEI). A failed
    ///      transfer queues the funds instead of reverting, so an
    ///      uncooperative recipient can never block resolution.
    function _payout(address to, address token, uint256 amount) internal {
        if (amount == 0) return;

        bool ok;
        if (token == address(0)) {
            (ok,) = to.call{value: amount}("");
        } else {
            // Equivalent of SafeERC20 semantics, without reverting on failure
            // (e.g. USDC blocklist): success = call succeeded AND (no return
            // data OR decoded true).
            (bool callOk, bytes memory ret) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
            ok = callOk && (ret.length == 0 || abi.decode(ret, (bool)));
        }

        if (!ok) {
            withdrawable[to][token] += amount;
            emit WithdrawalQueued(to, token, amount);
        }
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setFeeBps(uint16 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh(bps, MAX_FEE_BPS);
        feeBps = bps;
        emit FeeUpdated(bps);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setResolver(address resolver_) external onlyOwner {
        if (resolver_ == address(0)) revert ZeroAddress();
        resolver = resolver_;
        emit ResolverUpdated(resolver_);
    }

    function setToken(address token, bool allowed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }

    function setWindows(uint64 releaseWindow_, uint64 sellerResponseWindow_) external onlyOwner {
        if (releaseWindow_ == 0 || sellerResponseWindow_ == 0) revert ZeroWindow();
        releaseWindow = releaseWindow_;
        sellerResponseWindow = sellerResponseWindow_;
        emit WindowsUpdated(releaseWindow_, sellerResponseWindow_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @inheritdoc IEscrowMarket
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return _listings[listingId];
    }

    /// @inheritdoc IEscrowMarket
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return _escrows[escrowId];
    }

    // ---------------------------------------------------------------------
    // Internal guards
    // ---------------------------------------------------------------------

    function _requireActiveListing(uint256 listingId) internal view returns (Listing storage listing) {
        listing = _listings[listingId];
        if (listing.seller == address(0)) revert ListingNotFound(listingId);
        if (!listing.active) revert ListingNotActive(listingId);
    }

    function _requireEscrow(uint256 escrowId) internal view returns (Escrow storage escrow) {
        escrow = _escrows[escrowId];
        if (escrow.status == EscrowStatus.None) revert EscrowNotFound(escrowId);
    }

    function _requireOpen(uint256 escrowId, Escrow storage escrow) internal view {
        if (escrow.status != EscrowStatus.Funded && escrow.status != EscrowStatus.Disputed) {
            revert InvalidStatus(escrowId, uint8(escrow.status));
        }
    }

    function _requireParty(Escrow storage escrow) internal view {
        if (msg.sender != escrow.buyer && msg.sender != escrow.seller) revert NotParty(msg.sender);
    }
}
