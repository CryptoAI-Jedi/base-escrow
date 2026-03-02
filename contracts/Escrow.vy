# @version 0.4.0
"""
@title Simple Escrow Marketplace MVP
@notice One escrow per contract instance:
        - buyer deposits ETH
        - seller can withdraw only after buyer release OR arbiter release
        - buyer can refund only after arbiter approves refund
@dev    Production-clean MVP with explicit state machine + reentrancy guard
"""

from vyper.interfaces import ERC20  # not used now; reserved for future token escrow

event Deposited:
    buyer: indexed(address)
    amount: uint256

event Released:
    by: indexed(address)
    to: indexed(address)
    amount: uint256

event RefundApproved:
    by: indexed(address)

event Refunded:
    by: indexed(address)
    to: indexed(address)
    amount: uint256

event Disputed:
    by: indexed(address)

event ArbiterUpdated:
    old_arbiter: indexed(address)
    new_arbiter: indexed(address)

event SellerUpdated:
    old_seller: indexed(address)
    new_seller: indexed(address)

event BuyerUpdated:
    old_buyer: indexed(address)
    new_buyer: indexed(address)


enum Status:
    AWAITING_DEPOSIT
    FUNDED
    RELEASED
    REFUNDED
    DISPUTED


buyer: public(address)
seller: public(address)
arbiter: public(address)

amount: public(uint256)
status: public(Status)

lock: uint256  # simple nonReentrant lock


@deploy
def __init__(_buyer: address, _seller: address, _arbiter: address):
    """
    @param _buyer   Buyer address
    @param _seller  Seller address
    @param _arbiter Arbiter/mediator address
    """
    assert _buyer != empty(address), "buyer=0"
    assert _seller != empty(address), "seller=0"
    assert _arbiter != empty(address), "arbiter=0"
    assert _buyer != _seller, "buyer==seller"

    self.buyer = _buyer
    self.seller = _seller
    self.arbiter = _arbiter
    self.status = Status.AWAITING_DEPOSIT


@internal
def _nonreentrant_enter():
    assert self.lock == 0, "reentrancy"
    self.lock = 1


@internal
def _nonreentrant_exit():
    self.lock = 0


@external
@payable
def deposit():
    """
    @notice Buyer deposits ETH into escrow (single-shot funding).
    """
    self._nonreentrant_enter()

    assert msg.sender == self.buyer, "only buyer"
    assert self.status == Status.AWAITING_DEPOSIT, "bad status"
    assert msg.value > 0, "value=0"

    self.amount = msg.value
    self.status = Status.FUNDED

    log Deposited(self.buyer, msg.value)

    self._nonreentrant_exit()


@external
def mark_dispute():
    """
    @notice Buyer or seller can mark escrow as disputed after funding.
    """
    assert self.status == Status.FUNDED, "bad status"
    assert msg.sender == self.buyer or msg.sender == self.seller, "unauthorized"

    self.status = Status.DISPUTED
    log Disputed(msg.sender)


@external
def approve_refund():
    """
    @notice Arbiter approves refund path.
    @dev    Moves DISPUTED/FUNDED -> DISPUTED as refund-intent marker.
            Keeping minimal MVP: approval is signaled by status DISPUTED.
    """
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == Status.FUNDED or self.status == Status.DISPUTED, "bad status"

    self.status = Status.DISPUTED
    log RefundApproved(msg.sender)


@external
def release():
    """
    @notice Release escrow to seller.
    @dev    Allowed by buyer (happy path) OR arbiter (dispute resolution).
    """
    self._nonreentrant_enter()

    assert self.status == Status.FUNDED or self.status == Status.DISPUTED, "bad status"
    assert msg.sender == self.buyer or msg.sender == self.arbiter, "unauthorized"

    amt: uint256 = self.amount
    assert amt > 0, "no funds"

    self.amount = 0
    self.status = Status.RELEASED

    send(self.seller, amt)
    log Released(msg.sender, self.seller, amt)

    self._nonreentrant_exit()


@external
def refund():
    """
    @notice Refund escrow to buyer.
    @dev    Only arbiter can execute refund (strict MVP safety).
            If you want buyer-triggered refund-after-approval, add a separate boolean.
    """
    self._nonreentrant_enter()

    assert self.status == Status.DISPUTED, "not disputed"
    assert msg.sender == self.arbiter, "only arbiter"

    amt: uint256 = self.amount
    assert amt > 0, "no funds"

    self.amount = 0
    self.status = Status.REFUNDED

    send(self.buyer, amt)
    log Refunded(msg.sender, self.buyer, amt)

    self._nonreentrant_exit()


# --- Optional admin updates (only arbiter) for operational recovery in MVP ---

@external
def set_buyer(_buyer: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == Status.AWAITING_DEPOSIT, "already funded"
    assert _buyer != empty(address), "buyer=0"
    old: address = self.buyer
    self.buyer = _buyer
    log BuyerUpdated(old, _buyer)


@external
def set_seller(_seller: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == Status.AWAITING_DEPOSIT, "already funded"
    assert _seller != empty(address), "seller=0"
    old: address = self.seller
    self.seller = _seller
    log SellerUpdated(old, _seller)


@external
def set_arbiter(_arbiter: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert _arbiter != empty(address), "arbiter=0"
    old: address = self.arbiter
    self.arbiter = _arbiter
    log ArbiterUpdated(old, _arbiter)
