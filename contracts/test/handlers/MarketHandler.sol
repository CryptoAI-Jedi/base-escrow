// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {EscrowMarket} from "../../src/EscrowMarket.sol";
import {IEscrowMarket} from "../../src/interfaces/IEscrowMarket.sol";
import {MockERC20, ToggleReceiver} from "../mocks/Mocks.sol";

/// @dev Invariant-test handler: performs randomized but state-aware actions
///      against the market so the invariant contract can verify global
///      accounting. One buyer is a contract whose ETH acceptance toggles,
///      exercising the pull-payment fallback path.
contract MarketHandler is Test {
    EscrowMarket public market;
    MockERC20 public usdc;
    address public owner;
    address public resolver;
    address public treasury;

    address[] internal sellers;
    address[] internal buyers;
    ToggleReceiver public toggleBuyer;

    uint256[] public listingIds;
    uint256[] public escrowIds;

    // Ghost accounting
    mapping(uint256 => uint8) public recordedTerminal; // escrowId => terminal status (0 = none)
    uint256 public ghostFeesEth; // fees paid out to treasury (ETH)
    uint256 public ghostFeesUsdc; // fees paid out to treasury (USDC)

    constructor(EscrowMarket market_, MockERC20 usdc_, address owner_, address resolver_, address treasury_) {
        market = market_;
        usdc = usdc_;
        owner = owner_;
        resolver = resolver_;
        treasury = treasury_;

        for (uint256 i = 0; i < 2; i++) {
            sellers.push(makeAddr(string(abi.encodePacked("seller", i))));
        }
        for (uint256 i = 0; i < 3; i++) {
            address b = makeAddr(string(abi.encodePacked("buyer", i)));
            buyers.push(b);
            vm.deal(b, type(uint96).max);
            usdc.mint(b, type(uint96).max);
        }
        toggleBuyer = new ToggleReceiver();
        vm.deal(address(toggleBuyer), type(uint96).max);
    }

    // -- views for the invariant contract -----------------------------------

    function escrowCount() external view returns (uint256) {
        return escrowIds.length;
    }

    function accountCount() external view returns (uint256) {
        return sellers.length + buyers.length + 2; // + toggleBuyer + treasury
    }

    function accountAt(uint256 i) external view returns (address) {
        if (i < sellers.length) return sellers[i];
        i -= sellers.length;
        if (i < buyers.length) return buyers[i];
        i -= buyers.length;
        return i == 0 ? address(toggleBuyer) : treasury;
    }

    // -- actions -------------------------------------------------------------

    function createListing(uint256 seed) external {
        address seller = sellers[seed % sellers.length];
        bool eth = (seed >> 8) % 2 == 0;
        uint96 price = uint96(bound(seed >> 16, 1, 100 ether));

        vm.prank(seller);
        uint256 id = market.createListing(eth ? address(0) : address(usdc), price, bytes32("cat"), "cid");
        listingIds.push(id);
    }

    function buy(uint256 seed) external {
        if (listingIds.length == 0) return;
        uint256 listingId = listingIds[seed % listingIds.length];
        IEscrowMarket.Listing memory listing = market.getListing(listingId);
        if (!listing.active) return;

        if (listing.token == address(0)) {
            // Alternate between EOA buyers and the toggling contract buyer.
            if ((seed >> 8) % 4 == 0) {
                toggleBuyer.setAccept(true);
                uint256 id = toggleBuyer.doBuy{value: listing.price}(market, listingId);
                escrowIds.push(id);
            } else {
                address buyer = buyers[(seed >> 8) % buyers.length];
                vm.prank(buyer);
                uint256 id = market.buy{value: listing.price}(listingId);
                escrowIds.push(id);
            }
        } else {
            address buyer = buyers[(seed >> 8) % buyers.length];
            vm.startPrank(buyer);
            usdc.approve(address(market), listing.price);
            uint256 id = market.buyERC20(listingId);
            vm.stopPrank();
            escrowIds.push(id);
        }
    }

    function cancelListing(uint256 seed) external {
        if (listingIds.length == 0) return;
        uint256 listingId = listingIds[seed % listingIds.length];
        IEscrowMarket.Listing memory listing = market.getListing(listingId);
        if (!listing.active) return;
        vm.prank(listing.seller);
        market.cancelListing(listingId);
    }

    function release(uint256 seed) external {
        (uint256 escrowId, IEscrowMarket.Escrow memory escrow) = _pickOpenEscrow(seed);
        if (escrowId == 0) return;

        _recordFee(escrow);
        vm.prank(escrow.buyer);
        market.release(escrowId);
        recordedTerminal[escrowId] = uint8(IEscrowMarket.EscrowStatus.Released);
    }

    function openDispute(uint256 seed) external {
        (uint256 escrowId, IEscrowMarket.Escrow memory escrow) = _pickOpenEscrow(seed);
        if (escrowId == 0) return;
        if (escrow.status != IEscrowMarket.EscrowStatus.Funded) return;
        if (block.timestamp >= escrow.releaseDeadline) return;

        address party = (seed >> 8) % 2 == 0 ? escrow.buyer : escrow.seller;
        vm.prank(party);
        market.openDispute(escrowId, "bafyevidence");
    }

    function submitEvidence(uint256 seed) external {
        (uint256 escrowId, IEscrowMarket.Escrow memory escrow) = _pickOpenEscrow(seed);
        if (escrowId == 0) return;
        if (escrow.status != IEscrowMarket.EscrowStatus.Disputed) return;

        vm.prank((seed >> 8) % 2 == 0 ? escrow.buyer : escrow.seller);
        market.submitEvidence(escrowId, "bafymore");
    }

    function resolveRelease(uint256 seed) external {
        (uint256 escrowId, IEscrowMarket.Escrow memory escrow) = _pickOpenEscrow(seed);
        if (escrowId == 0) return;
        if (escrow.status == IEscrowMarket.EscrowStatus.Funded && block.timestamp <= escrow.releaseDeadline) {
            return;
        }

        _recordFee(escrow);
        vm.prank(resolver);
        market.resolveRelease(escrowId, bytes32("REASON"));
        recordedTerminal[escrowId] = uint8(IEscrowMarket.EscrowStatus.Released);
    }

    function resolveRefund(uint256 seed) external {
        (uint256 escrowId, IEscrowMarket.Escrow memory escrow) = _pickOpenEscrow(seed);
        if (escrowId == 0) return;
        if (escrow.status != IEscrowMarket.EscrowStatus.Disputed) return;

        // Half the time the contract buyer rejects ETH, forcing the
        // pull-payment fallback.
        if (escrow.buyer == address(toggleBuyer)) {
            toggleBuyer.setAccept((seed >> 8) % 2 == 0);
        }

        vm.prank(resolver);
        market.resolveRefund(escrowId, bytes32("REASON"));
        recordedTerminal[escrowId] = uint8(IEscrowMarket.EscrowStatus.Refunded);
    }

    function withdrawQueued(uint256 seed) external {
        if (market.withdrawable(address(toggleBuyer), address(0)) == 0) return;
        toggleBuyer.setAccept(true);
        toggleBuyer.doWithdraw(market);
        seed; // silence unused warning
    }

    function setFee(uint256 seed) external {
        vm.prank(owner);
        market.setFeeBps(uint16(bound(seed, 0, market.MAX_FEE_BPS())));
    }

    function warp(uint256 seed) external {
        vm.warp(block.timestamp + bound(seed, 1 hours, 10 days));
    }

    // -- internals -----------------------------------------------------------

    function _pickOpenEscrow(uint256 seed)
        internal
        view
        returns (uint256 escrowId, IEscrowMarket.Escrow memory escrow)
    {
        if (escrowIds.length == 0) return (0, escrow);
        escrowId = escrowIds[seed % escrowIds.length];
        escrow = market.getEscrow(escrowId);
        if (
            escrow.status != IEscrowMarket.EscrowStatus.Funded
                && escrow.status != IEscrowMarket.EscrowStatus.Disputed
        ) {
            return (0, escrow);
        }
    }

    function _recordFee(IEscrowMarket.Escrow memory escrow) internal {
        if (escrow.token == address(0)) ghostFeesEth += escrow.feeAmount;
        else ghostFeesUsdc += escrow.feeAmount;
    }
}
