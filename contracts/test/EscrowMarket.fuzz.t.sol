// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EscrowMarketTestBase} from "./EscrowMarket.t.sol";
import {IEscrowMarket} from "../src/interfaces/IEscrowMarket.sol";
import "../src/libraries/Errors.sol";

contract EscrowMarketFuzzTest is EscrowMarketTestBase {
    function testFuzz_feeMath_releaseSplitsExactly(uint96 price, uint16 bps) public {
        price = uint96(bound(price, 1, type(uint96).max));
        bps = uint16(bound(bps, 0, market.MAX_FEE_BPS()));

        vm.prank(owner);
        market.setFeeBps(bps);

        vm.prank(seller);
        uint256 listingId = market.createListing(address(0), price, CATEGORY, CID);

        vm.deal(buyer, price);
        vm.prank(buyer);
        uint256 escrowId = market.buy{value: price}(listingId);

        uint96 expectedFee = uint96((uint256(price) * bps) / 10_000);
        assertEq(market.getEscrow(escrowId).feeAmount, expectedFee);
        assertLe(expectedFee, uint256(price) * 500 / 10_000, "fee exceeds hard cap");

        vm.prank(buyer);
        market.release(escrowId);

        // Seller + treasury receive exactly the escrowed amount, no dust left.
        assertEq(seller.balance, price - expectedFee);
        assertEq(treasury.balance, expectedFee);
        assertEq(address(market).balance, 0);
    }

    function testFuzz_refundReturnsFullAmount(uint96 price, uint16 bps) public {
        price = uint96(bound(price, 1, type(uint96).max));
        bps = uint16(bound(bps, 0, market.MAX_FEE_BPS()));

        vm.prank(owner);
        market.setFeeBps(bps);

        vm.prank(seller);
        uint256 listingId = market.createListing(address(0), price, CATEGORY, CID);

        vm.deal(buyer, price);
        vm.prank(buyer);
        uint256 escrowId = market.buy{value: price}(listingId);

        vm.prank(buyer);
        market.openDispute(escrowId, "bafyevidence");

        vm.prank(resolver);
        market.resolveRefund(escrowId, REASON);

        // Fee is never charged on refunds.
        assertEq(buyer.balance, price);
        assertEq(treasury.balance, 0);
        assertEq(address(market).balance, 0);
    }

    /// @dev openDispute is valid strictly before the release deadline;
    ///      resolveRelease (timeout path) strictly after. At no timestamp are
    ///      both valid.
    function testFuzz_deadlineBoundary_noOverlap(uint64 elapsed) public {
        elapsed = uint64(bound(elapsed, 0, 2 * RELEASE_WINDOW));
        uint256 escrowId = _buyEth();
        uint64 deadline = market.getEscrow(escrowId).releaseDeadline;

        vm.warp(uint256(deadline) - RELEASE_WINDOW + elapsed);

        bool disputeAllowed = block.timestamp < deadline;
        bool timeoutAllowed = block.timestamp > deadline;
        assertFalse(disputeAllowed && timeoutAllowed);

        // Probe resolveRelease first via a snapshot so state is unchanged.
        uint256 snapshot = vm.snapshotState();
        vm.prank(resolver);
        if (timeoutAllowed) {
            market.resolveRelease(escrowId, REASON);
            assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Released));
        } else {
            vm.expectRevert(abi.encodeWithSelector(DeadlineNotReached.selector, deadline));
            market.resolveRelease(escrowId, REASON);
        }
        vm.revertToState(snapshot);

        vm.prank(buyer);
        if (disputeAllowed) {
            market.openDispute(escrowId, "bafyevidence");
            assertEq(uint8(market.getEscrow(escrowId).status), uint8(IEscrowMarket.EscrowStatus.Disputed));
        } else {
            vm.expectRevert(abi.encodeWithSelector(PastDeadline.selector, deadline));
            market.openDispute(escrowId, "bafyevidence");
        }
    }

    function testFuzz_strangerCannotTouchEscrow(address stranger) public {
        vm.assume(
            stranger != buyer && stranger != seller && stranger != resolver && stranger != owner
                && stranger != address(0)
        );
        uint256 escrowId = _buyEth();

        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotBuyer.selector, stranger));
        market.release(escrowId);
        vm.expectRevert(abi.encodeWithSelector(NotParty.selector, stranger));
        market.openDispute(escrowId, "cid");
        vm.expectRevert(abi.encodeWithSelector(NotResolver.selector, stranger));
        market.resolveRelease(escrowId, REASON);
        vm.expectRevert(abi.encodeWithSelector(NotResolver.selector, stranger));
        market.resolveRefund(escrowId, REASON);
        vm.stopPrank();
    }

    function testFuzz_erc20RoundTrip(uint96 price, uint16 bps) public {
        price = uint96(bound(price, 1, 1_000_000_000e6));
        bps = uint16(bound(bps, 0, market.MAX_FEE_BPS()));

        vm.prank(owner);
        market.setFeeBps(bps);

        uint256 listingId = _createUsdcListing(price);
        usdc.mint(buyer, price);

        vm.startPrank(buyer);
        usdc.approve(address(market), price);
        uint256 escrowId = market.buyERC20(listingId);
        market.release(escrowId);
        vm.stopPrank();

        uint96 expectedFee = uint96((uint256(price) * bps) / 10_000);
        assertEq(usdc.balanceOf(seller), price - expectedFee);
        assertEq(usdc.balanceOf(treasury), expectedFee);
        assertEq(usdc.balanceOf(address(market)), 0);
    }
}
