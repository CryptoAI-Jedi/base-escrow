// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ---------------------------------------------------------------------------
// Shared custom errors for the Base Escrow marketplace
// ---------------------------------------------------------------------------

error ZeroAddress();
error ZeroPrice();
error TokenNotAllowed(address token);
error ListingNotFound(uint256 listingId);
error ListingNotActive(uint256 listingId);
error NotSeller(address caller);
error SelfPurchase();
error WrongValue(uint256 expected, uint256 actual);
error NonZeroValue();
error UnexpectedTransferAmount(uint256 expected, uint256 actual);
error EscrowNotFound(uint256 escrowId);
error InvalidStatus(uint256 escrowId, uint8 status);
error NotBuyer(address caller);
error NotParty(address caller);
error NotResolver(address caller);
error PastDeadline(uint64 deadline);
error DeadlineNotReached(uint64 deadline);
error FeeTooHigh(uint16 bps, uint16 maxBps);
error ZeroWindow();
error NothingToWithdraw();
error NativeTransferFailed(address to, uint256 amount);
