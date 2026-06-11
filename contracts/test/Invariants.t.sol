// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {EscrowMarket} from "../src/EscrowMarket.sol";
import {IEscrowMarket} from "../src/interfaces/IEscrowMarket.sol";
import {MockERC20} from "./mocks/Mocks.sol";
import {MarketHandler} from "./handlers/MarketHandler.sol";

contract InvariantsTest is StdInvariant, Test {
    EscrowMarket internal market;
    MockERC20 internal usdc;
    MarketHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal resolver = makeAddr("resolver");
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        market = new EscrowMarket(owner, resolver, treasury, 7 days, 3 days);
        usdc = new MockERC20();
        vm.prank(owner);
        market.setToken(address(usdc), true);

        handler = new MarketHandler(market, usdc, owner, resolver, treasury);
        targetContract(address(handler));
    }

    /// @dev Exact solvency: the market holds precisely the open escrow
    ///      amounts plus all queued (pull-payment) balances — no leak, no
    ///      stuck surplus.
    function invariant_solvency_exact() public view {
        (uint256 openEth, uint256 openUsdc) = _sumOpenEscrows();
        (uint256 queuedEth, uint256 queuedUsdc) = _sumQueued();

        assertEq(address(market).balance, openEth + queuedEth, "ETH solvency");
        assertEq(usdc.balanceOf(address(market)), openUsdc + queuedUsdc, "USDC solvency");
    }

    /// @dev Terminal states are absorbing: once Released/Refunded, an escrow
    ///      never changes again.
    function invariant_terminalStatesAbsorbing() public view {
        uint256 count = handler.escrowCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 escrowId = handler.escrowIds(i);
            uint8 recorded = handler.recordedTerminal(escrowId);
            if (recorded != 0) {
                assertEq(uint8(market.getEscrow(escrowId).status), recorded, "terminal state mutated");
            }
        }
    }

    /// @dev The treasury receives exactly the snapshotted fees of released
    ///      escrows — never more (treasury is an EOA, so nothing queues).
    function invariant_treasuryReceivesExactFees() public view {
        assertEq(treasury.balance, handler.ghostFeesEth(), "ETH fees");
        assertEq(usdc.balanceOf(treasury), handler.ghostFeesUsdc(), "USDC fees");
    }

    /// @dev Every escrow the handler created exists, and fee never exceeds
    ///      the hard cap relative to its amount.
    function invariant_escrowWellFormed() public view {
        uint256 count = handler.escrowCount();
        for (uint256 i = 0; i < count; i++) {
            IEscrowMarket.Escrow memory escrow = market.getEscrow(handler.escrowIds(i));
            assertTrue(escrow.status != IEscrowMarket.EscrowStatus.None, "escrow vanished");
            assertLe(
                uint256(escrow.feeAmount), (uint256(escrow.amount) * market.MAX_FEE_BPS()) / 10_000, "fee cap"
            );
        }
    }

    // -- accounting helpers --------------------------------------------------

    function _sumOpenEscrows() internal view returns (uint256 openEth, uint256 openUsdc) {
        uint256 count = handler.escrowCount();
        for (uint256 i = 0; i < count; i++) {
            IEscrowMarket.Escrow memory escrow = market.getEscrow(handler.escrowIds(i));
            if (
                escrow.status == IEscrowMarket.EscrowStatus.Funded
                    || escrow.status == IEscrowMarket.EscrowStatus.Disputed
            ) {
                if (escrow.token == address(0)) openEth += escrow.amount;
                else openUsdc += escrow.amount;
            }
        }
    }

    function _sumQueued() internal view returns (uint256 queuedEth, uint256 queuedUsdc) {
        uint256 count = handler.accountCount();
        for (uint256 i = 0; i < count; i++) {
            address account = handler.accountAt(i);
            queuedEth += market.withdrawable(account, address(0));
            queuedUsdc += market.withdrawable(account, address(usdc));
        }
    }
}
