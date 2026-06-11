// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {EscrowMarket} from "../src/EscrowMarket.sol";
import {IEscrowMarket} from "../src/interfaces/IEscrowMarket.sol";
import "../src/libraries/Errors.sol";
import {
    MockERC20,
    BlocklistToken,
    ReturnFalseToken,
    FeeOnTransferToken,
    ToggleReceiver,
    ReentrantReceiver
} from "./mocks/Mocks.sol";

contract EscrowMarketTestBase is Test {
    EscrowMarket internal market;
    MockERC20 internal usdc;

    address internal owner = makeAddr("owner");
    address internal resolver = makeAddr("resolver");
    address internal treasury = makeAddr("treasury");
    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");
    address internal rando = makeAddr("rando");

    uint64 internal constant RELEASE_WINDOW = 7 days;
    uint64 internal constant RESPONSE_WINDOW = 3 days;
    uint96 internal constant PRICE = 1 ether;
    bytes32 internal constant CATEGORY = keccak256("electronics");
    string internal constant CID = "bafybeigdyrlisting";
    bytes32 internal constant REASON = bytes32("AUTO_RELEASE_TIMEOUT");

    function setUp() public virtual {
        market = new EscrowMarket(owner, resolver, treasury, RELEASE_WINDOW, RESPONSE_WINDOW);
        usdc = new MockERC20();

        vm.prank(owner);
        market.setToken(address(usdc), true);

        vm.deal(buyer, 100 ether);
        vm.deal(rando, 100 ether);
        usdc.mint(buyer, 1_000_000e6);
    }

    // -- helpers -----------------------------------------------------------

    function _createEthListing() internal returns (uint256) {
        vm.prank(seller);
        return market.createListing(address(0), PRICE, CATEGORY, CID);
    }

    function _createUsdcListing(uint96 price) internal returns (uint256) {
        vm.prank(seller);
        return market.createListing(address(usdc), price, CATEGORY, CID);
    }

    function _buyEth() internal returns (uint256 escrowId) {
        uint256 listingId = _createEthListing();
        vm.prank(buyer);
        escrowId = market.buy{value: PRICE}(listingId);
    }

    function _buyAndDispute(address by) internal returns (uint256 escrowId) {
        escrowId = _buyEth();
        vm.prank(by);
        market.openDispute(escrowId, "bafyevidence");
    }
}

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

contract ConstructorTest is EscrowMarketTestBase {
    function test_initialState() public view {
        assertEq(market.owner(), owner);
        assertEq(market.resolver(), resolver);
        assertEq(market.treasury(), treasury);
        assertEq(market.releaseWindow(), RELEASE_WINDOW);
        assertEq(market.sellerResponseWindow(), RESPONSE_WINDOW);
        assertEq(market.feeBps(), 0);
        assertEq(market.nextListingId(), 1);
        assertEq(market.nextEscrowId(), 1);
    }

    function test_revert_zeroResolver() public {
        vm.expectRevert(ZeroAddress.selector);
        new EscrowMarket(owner, address(0), treasury, RELEASE_WINDOW, RESPONSE_WINDOW);
    }

    function test_revert_zeroTreasury() public {
        vm.expectRevert(ZeroAddress.selector);
        new EscrowMarket(owner, resolver, address(0), RELEASE_WINDOW, RESPONSE_WINDOW);
    }

    function test_revert_zeroWindows() public {
        vm.expectRevert(ZeroWindow.selector);
        new EscrowMarket(owner, resolver, treasury, 0, RESPONSE_WINDOW);
        vm.expectRevert(ZeroWindow.selector);
        new EscrowMarket(owner, resolver, treasury, RELEASE_WINDOW, 0);
    }
}

// ---------------------------------------------------------------------------
// Listings
// ---------------------------------------------------------------------------

contract ListingTest is EscrowMarketTestBase {
    function test_createListing_eth() public {
        vm.expectEmit(true, true, true, true);
        emit IEscrowMarket.ListingCreated(1, seller, address(0), PRICE, CATEGORY, CID);
        uint256 id = _createEthListing();

        assertEq(id, 1);
        assertEq(market.nextListingId(), 2);
        IEscrowMarket.Listing memory listing = market.getListing(id);
        assertEq(listing.seller, seller);
        assertEq(listing.token, address(0));
        assertEq(listing.price, PRICE);
        assertEq(listing.category, CATEGORY);
        assertEq(listing.metadataCID, CID);
        assertTrue(listing.active);
    }

    function test_createListing_whitelistedToken() public {
        uint256 id = _createUsdcListing(100e6);
        assertEq(market.getListing(id).token, address(usdc));
    }

    function test_revert_createListing_zeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(ZeroPrice.selector);
        market.createListing(address(0), 0, CATEGORY, CID);
    }

    function test_revert_createListing_tokenNotAllowed() public {
        MockERC20 other = new MockERC20();
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, address(other)));
        market.createListing(address(other), PRICE, CATEGORY, CID);
    }

    function test_updateListing() public {
        uint256 id = _createEthListing();
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit IEscrowMarket.ListingUpdated(id, 2 ether, "newcid");
        market.updateListing(id, 2 ether, "newcid");

        IEscrowMarket.Listing memory listing = market.getListing(id);
        assertEq(listing.price, 2 ether);
        assertEq(listing.metadataCID, "newcid");
    }

    function test_updateListing_doesNotAffectOpenEscrow() public {
        uint256 listingId = _createEthListing();
        vm.prank(buyer);
        uint256 escrowId = market.buy{value: PRICE}(listingId);

        vm.prank(seller);
        market.updateListing(listingId, 5 ether, CID);

        assertEq(market.getEscrow(escrowId).amount, PRICE);
    }

    function test_revert_updateListing_notSeller() public {
        uint256 id = _createEthListing();
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotSeller.selector, rando));
        market.updateListing(id, 2 ether, CID);
    }

    function test_revert_updateListing_zeroPrice() public {
        uint256 id = _createEthListing();
        vm.prank(seller);
        vm.expectRevert(ZeroPrice.selector);
        market.updateListing(id, 0, CID);
    }

    function test_revert_updateListing_notFound() public {
        vm.expectRevert(abi.encodeWithSelector(ListingNotFound.selector, 99));
        market.updateListing(99, PRICE, CID);
    }

    function test_cancelListing() public {
        uint256 id = _createEthListing();
        vm.prank(seller);
        vm.expectEmit(true, false, false, false);
        emit IEscrowMarket.ListingCancelled(id);
        market.cancelListing(id);

        assertFalse(market.getListing(id).active);
    }

    function test_revert_cancelListing_notSeller() public {
        uint256 id = _createEthListing();
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotSeller.selector, rando));
        market.cancelListing(id);
    }

    function test_revert_cancelListing_alreadyCancelled() public {
        uint256 id = _createEthListing();
        vm.startPrank(seller);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(ListingNotActive.selector, id));
        market.cancelListing(id);
        vm.stopPrank();
    }
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

contract BuyTest is EscrowMarketTestBase {
    function test_buy_eth() public {
        uint256 listingId = _createEthListing();

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit IEscrowMarket.EscrowCreated(
            1, listingId, buyer, seller, address(0), PRICE, 0, uint64(block.timestamp) + RELEASE_WINDOW
        );
        uint256 escrowId = market.buy{value: PRICE}(listingId);

        assertEq(escrowId, 1);
        assertEq(address(market).balance, PRICE);

        IEscrowMarket.Escrow memory escrow = market.getEscrow(escrowId);
        assertEq(escrow.listingId, listingId);
        assertEq(escrow.buyer, buyer);
        assertEq(escrow.seller, seller);
        assertEq(escrow.token, address(0));
        assertEq(escrow.amount, PRICE);
        assertEq(escrow.feeAmount, 0);
        assertEq(uint8(escrow.status), uint8(IEscrowMarket.EscrowStatus.Funded));
        assertEq(escrow.releaseDeadline, uint64(block.timestamp) + RELEASE_WINDOW);
        assertEq(escrow.sellerResponseDeadline, 0);
        assertEq(escrow.disputedBy, address(0));
    }

    function test_buy_snapshotsFee() public {
        vm.prank(owner);
        market.setFeeBps(250); // 2.5%

        uint256 escrowId = _buyEth();
        assertEq(market.getEscrow(escrowId).feeAmount, (uint256(PRICE) * 250) / 10_000);

        // Later fee changes do not affect existing escrows.
        vm.prank(owner);
        market.setFeeBps(500);
        assertEq(market.getEscrow(escrowId).feeAmount, (uint256(PRICE) * 250) / 10_000);
    }

    function test_buy_listingRemainsActiveForMoreBuyers() public {
        uint256 listingId = _createEthListing();
        vm.prank(buyer);
        market.buy{value: PRICE}(listingId);
        vm.prank(rando);
        uint256 second = market.buy{value: PRICE}(listingId);
        assertEq(second, 2);
    }

    function test_revert_buy_wrongValue() public {
        uint256 listingId = _createEthListing();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(WrongValue.selector, PRICE, PRICE - 1));
        market.buy{value: PRICE - 1}(listingId);
    }

    function test_revert_buy_notFound() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ListingNotFound.selector, 42));
        market.buy{value: PRICE}(42);
    }

    function test_revert_buy_cancelled() public {
        uint256 listingId = _createEthListing();
        vm.prank(seller);
        market.cancelListing(listingId);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ListingNotActive.selector, listingId));
        market.buy{value: PRICE}(listingId);
    }

    function test_revert_buy_erc20ListingViaEthPath() public {
        uint256 listingId = _createUsdcListing(100e6);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, address(usdc)));
        market.buy{value: 100e6}(listingId);
    }

    function test_revert_buy_selfPurchase() public {
        uint256 listingId = _createEthListing();
        vm.deal(seller, PRICE);
        vm.prank(seller);
        vm.expectRevert(SelfPurchase.selector);
        market.buy{value: PRICE}(listingId);
    }

    function test_buyERC20() public {
        uint96 price = 100e6;
        uint256 listingId = _createUsdcListing(price);

        vm.startPrank(buyer);
        usdc.approve(address(market), price);
        uint256 escrowId = market.buyERC20(listingId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(market)), price);
        IEscrowMarket.Escrow memory escrow = market.getEscrow(escrowId);
        assertEq(escrow.token, address(usdc));
        assertEq(escrow.amount, price);
    }

    function test_revert_buyERC20_ethListing() public {
        uint256 listingId = _createEthListing();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, address(0)));
        market.buyERC20(listingId);
    }

    function test_revert_buyERC20_noApproval() public {
        uint256 listingId = _createUsdcListing(100e6);
        vm.prank(buyer);
        vm.expectRevert(); // SafeERC20 insufficient-allowance revert
        market.buyERC20(listingId);
    }

    function test_revert_buyERC20_feeOnTransfer() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        vm.prank(owner);
        market.setToken(address(fot), true);
        fot.mint(buyer, 1_000e6);

        vm.prank(seller);
        uint256 listingId = market.createListing(address(fot), 100e6, CATEGORY, CID);

        vm.startPrank(buyer);
        fot.approve(address(market), 100e6);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedTransferAmount.selector, 100e6, 100e6 - 1));
        market.buyERC20(listingId);
        vm.stopPrank();
    }
}

// ---------------------------------------------------------------------------
// Release (buyer)
// ---------------------------------------------------------------------------

contract ReleaseTest is EscrowMarketTestBase {
    function test_release_happyPath() public {
        uint256 escrowId = _buyEth();

        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit IEscrowMarket.Released(escrowId, buyer, PRICE, 0);
        market.release(escrowId);

        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
        assertEq(seller.balance, PRICE);
        assertEq(address(market).balance, 0);
    }

    function test_release_withFee() public {
        vm.prank(owner);
        market.setFeeBps(250);
        uint256 escrowId = _buyEth();
        uint96 fee = uint96((uint256(PRICE) * 250) / 10_000);

        vm.prank(buyer);
        market.release(escrowId);

        assertEq(seller.balance, PRICE - fee);
        assertEq(treasury.balance, fee);
    }

    function test_release_whileDisputed_concede() public {
        uint256 escrowId = _buyAndDispute(buyer);
        vm.prank(buyer);
        market.release(escrowId);
        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
        assertEq(seller.balance, PRICE);
    }

    function test_release_erc20() public {
        uint96 price = 100e6;
        uint256 listingId = _createUsdcListing(price);
        vm.startPrank(buyer);
        usdc.approve(address(market), price);
        uint256 escrowId = market.buyERC20(listingId);
        market.release(escrowId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(seller), price);
        assertEq(usdc.balanceOf(address(market)), 0);
    }

    function test_revert_release_notBuyer() public {
        uint256 escrowId = _buyEth();
        address[3] memory callers = [seller, resolver, rando];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(NotBuyer.selector, callers[i]));
            market.release(escrowId);
        }
    }

    function test_revert_release_terminalStates() public {
        uint256 escrowId = _buyEth();
        vm.prank(buyer);
        market.release(escrowId);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidStatus.selector, escrowId, uint8(IEscrowMarket.EscrowStatus.Released)
            )
        );
        market.release(escrowId);
    }

    function test_revert_release_unknownEscrow() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowNotFound.selector, 7));
        market.release(7);
    }
}

// ---------------------------------------------------------------------------
// Disputes & evidence
// ---------------------------------------------------------------------------

contract DisputeTest is EscrowMarketTestBase {
    function test_openDispute_byBuyer() public {
        uint256 escrowId = _buyEth();
        uint64 expectedDeadline = uint64(block.timestamp) + RESPONSE_WINDOW;

        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit IEscrowMarket.DisputeOpened(escrowId, buyer, "bafyevidence", expectedDeadline);
        market.openDispute(escrowId, "bafyevidence");

        IEscrowMarket.Escrow memory escrow = market.getEscrow(escrowId);
        assertEq(uint8(escrow.status), uint8(IEscrowMarket.EscrowStatus.Disputed));
        assertEq(escrow.sellerResponseDeadline, expectedDeadline);
        assertEq(escrow.evidenceCID, "bafyevidence");
        assertEq(escrow.disputedBy, buyer);
    }

    function test_openDispute_bySeller_emptyEvidence() public {
        uint256 escrowId = _buyEth();
        vm.prank(seller);
        market.openDispute(escrowId, "");
        assertEq(market.getEscrow(escrowId).disputedBy, seller);
    }

    function test_revert_openDispute_notParty() public {
        uint256 escrowId = _buyEth();
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotParty.selector, rando));
        market.openDispute(escrowId, "");
    }

    function test_revert_openDispute_alreadyDisputed() public {
        uint256 escrowId = _buyAndDispute(buyer);
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidStatus.selector, escrowId, uint8(IEscrowMarket.EscrowStatus.Disputed)
            )
        );
        market.openDispute(escrowId, "");
    }

    function test_revert_openDispute_atOrAfterDeadline() public {
        uint256 escrowId = _buyEth();
        uint64 deadline = market.getEscrow(escrowId).releaseDeadline;

        // Exactly at the deadline: dispute is no longer allowed...
        vm.warp(deadline);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(PastDeadline.selector, deadline));
        market.openDispute(escrowId, "");

        // ...and neither is it later.
        vm.warp(deadline + 1);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(PastDeadline.selector, deadline));
        market.openDispute(escrowId, "");
    }

    function test_submitEvidence() public {
        uint256 escrowId = _buyAndDispute(buyer);

        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit IEscrowMarket.EvidenceSubmitted(escrowId, seller, "bafyseller");
        market.submitEvidence(escrowId, "bafyseller");

        assertEq(market.getEscrow(escrowId).evidenceCID, "bafyseller");
    }

    function test_revert_submitEvidence_notDisputed() public {
        uint256 escrowId = _buyEth();
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidStatus.selector, escrowId, uint8(IEscrowMarket.EscrowStatus.Funded))
        );
        market.submitEvidence(escrowId, "cid");
    }

    function test_revert_submitEvidence_notParty() public {
        uint256 escrowId = _buyAndDispute(buyer);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotParty.selector, rando));
        market.submitEvidence(escrowId, "cid");
    }
}

// ---------------------------------------------------------------------------
// Resolver actions
// ---------------------------------------------------------------------------

contract ResolveTest is EscrowMarketTestBase {
    function test_resolveRelease_disputed() public {
        uint256 escrowId = _buyAndDispute(seller);

        vm.prank(resolver);
        vm.expectEmit(true, false, false, true);
        emit IEscrowMarket.Resolved(escrowId, 1, REASON);
        market.resolveRelease(escrowId, REASON);

        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
        assertEq(seller.balance, PRICE);
    }

    function test_resolveRelease_fundedPastDeadline() public {
        uint256 escrowId = _buyEth();
        vm.warp(market.getEscrow(escrowId).releaseDeadline + 1);

        vm.prank(resolver);
        market.resolveRelease(escrowId, REASON);
        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
    }

    function test_revert_resolveRelease_fundedBeforeDeadline() public {
        uint256 escrowId = _buyEth();
        uint64 deadline = market.getEscrow(escrowId).releaseDeadline;

        // Strictly before the deadline.
        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(DeadlineNotReached.selector, deadline));
        market.resolveRelease(escrowId, REASON);

        // Exactly at the deadline still not allowed (no overlap with openDispute).
        vm.warp(deadline);
        vm.prank(resolver);
        vm.expectRevert(abi.encodeWithSelector(DeadlineNotReached.selector, deadline));
        market.resolveRelease(escrowId, REASON);
    }

    function test_revert_resolveRelease_notResolver() public {
        uint256 escrowId = _buyAndDispute(buyer);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotResolver.selector, rando));
        market.resolveRelease(escrowId, REASON);
    }

    function test_revert_resolveRelease_terminal() public {
        uint256 escrowId = _buyEth();
        vm.prank(buyer);
        market.release(escrowId);

        vm.prank(resolver);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidStatus.selector, escrowId, uint8(IEscrowMarket.EscrowStatus.Released)
            )
        );
        market.resolveRelease(escrowId, REASON);
    }

    function test_resolveRefund() public {
        vm.prank(owner);
        market.setFeeBps(250);
        uint256 escrowId = _buyAndDispute(buyer);
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(resolver);
        vm.expectEmit(true, false, false, true);
        emit IEscrowMarket.Resolved(escrowId, 2, bytes32("SELLER_INACTIVE"));
        market.resolveRefund(escrowId, bytes32("SELLER_INACTIVE"));

        // Full amount, fee included, returns to the buyer.
        assertEq(buyer.balance, buyerBalanceBefore + PRICE);
        assertEq(treasury.balance, 0);
        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Refunded));
    }

    function test_revert_resolveRefund_notDisputed() public {
        uint256 escrowId = _buyEth();
        vm.prank(resolver);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidStatus.selector, escrowId, uint8(IEscrowMarket.EscrowStatus.Funded))
        );
        market.resolveRefund(escrowId, REASON);
    }

    function test_revert_resolveRefund_notResolver() public {
        uint256 escrowId = _buyAndDispute(buyer);
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(NotResolver.selector, rando));
        market.resolveRefund(escrowId, REASON);
    }
}

// ---------------------------------------------------------------------------
// Payout fallback & withdraw
// ---------------------------------------------------------------------------

contract WithdrawTest is EscrowMarketTestBase {
    function test_payoutFallback_revertingEthRecipient() public {
        // Buyer is a contract that rejects ETH; refund must queue, not revert.
        ToggleReceiver contractBuyer = new ToggleReceiver();
        vm.deal(address(this), PRICE);

        uint256 listingId = _createEthListing();
        uint256 escrowId = contractBuyer.doBuy{value: PRICE}(market, listingId);

        vm.prank(address(contractBuyer));
        market.openDispute(escrowId, "bafyevidence");

        contractBuyer.setAccept(false);
        vm.prank(resolver);
        vm.expectEmit(true, false, false, true);
        emit IEscrowMarket.WithdrawalQueued(address(contractBuyer), address(0), PRICE);
        market.resolveRefund(escrowId, REASON);

        // Terminal state reached despite the failed transfer.
        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Refunded));
        assertEq(market.withdrawable(address(contractBuyer), address(0)), PRICE);

        // Withdraw fails while still rejecting...
        vm.expectRevert(abi.encodeWithSelector(NativeTransferFailed.selector, address(contractBuyer), PRICE));
        contractBuyer.doWithdraw(market);

        // ...and succeeds once the recipient accepts ETH.
        contractBuyer.setAccept(true);
        contractBuyer.doWithdraw(market);
        assertEq(address(contractBuyer).balance, PRICE);
        assertEq(market.withdrawable(address(contractBuyer), address(0)), 0);
    }

    function test_payoutFallback_blocklistedErc20Recipient() public {
        BlocklistToken blockToken = new BlocklistToken();
        vm.prank(owner);
        market.setToken(address(blockToken), true);
        blockToken.mint(buyer, 1_000e6);

        vm.prank(seller);
        uint256 listingId = market.createListing(address(blockToken), 100e6, CATEGORY, CID);
        vm.startPrank(buyer);
        blockToken.approve(address(market), 100e6);
        uint256 escrowId = market.buyERC20(listingId);
        vm.stopPrank();

        // Seller gets blocklisted before release.
        blockToken.setBlocked(seller, true);
        vm.prank(buyer);
        market.release(escrowId);

        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
        assertEq(market.withdrawable(seller, address(blockToken)), 100e6);

        // Unblocked seller can pull.
        blockToken.setBlocked(seller, false);
        vm.prank(seller);
        market.withdraw(address(blockToken));
        assertEq(blockToken.balanceOf(seller), 100e6);
    }

    function test_payoutFallback_returnFalseToken() public {
        ReturnFalseToken soft = new ReturnFalseToken();
        vm.prank(owner);
        market.setToken(address(soft), true);
        soft.mint(buyer, 1_000e6);

        vm.prank(seller);
        uint256 listingId = market.createListing(address(soft), 100e6, CATEGORY, CID);
        vm.startPrank(buyer);
        soft.approve(address(market), 100e6);
        uint256 escrowId = market.buyERC20(listingId);
        vm.stopPrank();

        soft.setSoftFail(seller, true);
        vm.prank(buyer);
        market.release(escrowId);

        assertEq(market.withdrawable(seller, address(soft)), 100e6);
        assertEq(soft.balanceOf(seller), 0);
    }

    function test_reentrancy_blockedOnPayout() public {
        ReentrantReceiver attacker = new ReentrantReceiver(market);

        uint256 listingId = _createEthListing();
        uint256 escrowId = attacker.doBuy{value: PRICE}(listingId);
        vm.prank(address(attacker));
        market.openDispute(escrowId, "bafyevidence");

        attacker.setAttack(escrowId, true);
        vm.prank(resolver);
        market.resolveRefund(escrowId, REASON);

        // The reentrant release() attempt must have reverted (guard), and the
        // refund itself must have completed normally.
        assertTrue(attacker.reentryBlocked());
        assertEq(address(attacker).balance, PRICE);
        assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Refunded));
    }

    function test_revert_withdraw_nothing() public {
        vm.prank(rando);
        vm.expectRevert(NothingToWithdraw.selector);
        market.withdraw(address(0));
    }
}

// ---------------------------------------------------------------------------
// Admin & pause
// ---------------------------------------------------------------------------

contract AdminTest is EscrowMarketTestBase {
    function test_setFeeBps() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IEscrowMarket.FeeUpdated(500);
        market.setFeeBps(500);
        assertEq(market.feeBps(), 500);
    }

    function test_revert_setFeeBps_aboveCap() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(FeeTooHigh.selector, 501, 500));
        market.setFeeBps(501);
    }

    function test_setTreasury_setResolver_setWindows() public {
        address newAddr = makeAddr("new");
        vm.startPrank(owner);
        market.setTreasury(newAddr);
        market.setResolver(newAddr);
        market.setWindows(1 days, 1 days);
        vm.stopPrank();

        assertEq(market.treasury(), newAddr);
        assertEq(market.resolver(), newAddr);
        assertEq(market.releaseWindow(), 1 days);
        assertEq(market.sellerResponseWindow(), 1 days);
    }

    function test_revert_admin_zeroValues() public {
        vm.startPrank(owner);
        vm.expectRevert(ZeroAddress.selector);
        market.setTreasury(address(0));
        vm.expectRevert(ZeroAddress.selector);
        market.setResolver(address(0));
        vm.expectRevert(ZeroAddress.selector);
        market.setToken(address(0), true);
        vm.expectRevert(ZeroWindow.selector);
        market.setWindows(0, 1 days);
        vm.stopPrank();
    }

    function test_revert_admin_notOwner() public {
        vm.startPrank(rando);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando);
        vm.expectRevert(err);
        market.setFeeBps(100);
        vm.expectRevert(err);
        market.setTreasury(rando);
        vm.expectRevert(err);
        market.setResolver(rando);
        vm.expectRevert(err);
        market.setToken(address(usdc), false);
        vm.expectRevert(err);
        market.setWindows(1, 1);
        vm.expectRevert(err);
        market.pause();
        vm.stopPrank();
    }

    function test_ownership_twoStep() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        market.transferOwnership(newOwner);
        assertEq(market.owner(), owner); // not yet effective

        vm.prank(newOwner);
        market.acceptOwnership();
        assertEq(market.owner(), newOwner);
    }
}

contract PauseTest is EscrowMarketTestBase {
    uint256 internal disputedEscrowId;
    uint256 internal fundedEscrowId;
    uint256 internal listingId;

    function setUp() public override {
        super.setUp();
        disputedEscrowId = _buyAndDispute(buyer);
        fundedEscrowId = _buyEth();
        listingId = _createEthListing();

        vm.prank(owner);
        market.pause();
    }

    function test_pause_blocksNewListingsAndPurchases() public {
        vm.prank(seller);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        market.createListing(address(0), PRICE, CATEGORY, CID);

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        market.buy{value: PRICE}(listingId);

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        market.buyERC20(listingId);
    }

    function test_pause_neverBlocksExitPaths() public {
        // Dispute lifecycle continues while paused.
        vm.prank(seller);
        market.submitEvidence(disputedEscrowId, "bafyseller");

        vm.prank(buyer);
        market.openDispute(fundedEscrowId, "bafyevidence");

        vm.prank(resolver);
        market.resolveRefund(disputedEscrowId, REASON);

        vm.prank(buyer);
        market.release(fundedEscrowId);
    }

    function test_unpause_restores() public {
        vm.prank(owner);
        market.unpause();
        vm.prank(buyer);
        market.buy{value: PRICE}(listingId);
    }
}
