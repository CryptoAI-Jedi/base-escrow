# @version 0.4.3
"""
@title Simple Escrow Marketplace MVP
@notice One escrow per contract instance:
        - buyer deposits ETH
        - seller can withdraw only after buyer release OR arbiter release
        - buyer can refund only after arbiter approves refund
@dev    Production-clean MVP with explicit state machine + reentrancy guard
"""

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


STATUS_AWAITING_DEPOSIT: constant(uint256) = 0
STATUS_FUNDED: constant(uint256) = 1
STATUS_RELEASED: constant(uint256) = 2 
STATUS_REFUNDED: constant(uint256) = 3
STATUS_DISPUTED: constant(uint256) = 4

status: public(uint256)


buyer: public(address)
seller: public(address)
arbiter: public(address)

amount: public(uint256)

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
    self.status = STATUS_AWAITING_DEPOSIT


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
    assert self.status == STATUS_AWAITING_DEPOSIT, "bad status"
    assert msg.value > 0, "value=0"

    self.amount = msg.value
    self.status = STATUS_FUNDED

    log Deposited(buyer=self.buyer, amount=msg.value)

    self._nonreentrant_exit()


@external
def mark_dispute():
    """
    @notice Buyer or seller can mark escrow as disputed after funding.
    """
    assert self.status == STATUS_FUNDED, "bad status"
    assert msg.sender == self.buyer or msg.sender == self.seller, "unauthorized"

    self.status = STATUS_DISPUTED
    log Disputed(by=msg.sender)


@external
def approve_refund():
    """
    @notice Arbiter approves refund path.
    @dev    Moves DISPUTED/FUNDED -> DISPUTED as refund-intent marker.
            Keeping minimal MVP: approval is signaled by status DISPUTED.
    """
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == STATUS_FUNDED or self.status == STATUS_DISPUTED, "bad status"

    self.status = STATUS_DISPUTED
    log RefundApproved(by=msg.sender)


@external
def release():
    """
    @notice Release escrow to seller.
    @dev    Allowed by buyer (happy path) OR arbiter (dispute resolution).
    """
    self._nonreentrant_enter()

    assert self.status == STATUS_FUNDED or self.status == STATUS_DISPUTED, "bad status"
    assert msg.sender == self.buyer or msg.sender == self.arbiter, "unauthorized"

    amt: uint256 = self.amount
    assert amt > 0, "no funds"

    self.amount = 0
    self.status = STATUS_RELEASED

    send(self.seller, amt)
    log Released(by=msg.sender, to=self.seller, amount=amt)

    self._nonreentrant_exit()


@external
def refund():
    """
    @notice Refund escrow to buyer.
    @dev    Only arbiter can execute refund (strict MVP safety).
            If you want buyer-triggered refund-after-approval, add a separate boolean.
    """
    self._nonreentrant_enter()

    assert self.status == STATUS_DISPUTED, "not disputed"
    assert msg.sender == self.arbiter, "only arbiter"

    amt: uint256 = self.amount
    assert amt > 0, "no funds"

    self.amount = 0
    self.status = STATUS_REFUNDED

    send(self.buyer, amt)
    log Refunded(by=msg.sender, to=self.buyer, amount=amt)

    self._nonreentrant_exit()


# --- Optional admin updates (only arbiter) for operational recovery in MVP ---

@external
def set_buyer(_buyer: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == STATUS_AWAITING_DEPOSIT, "already funded"
    assert _buyer != empty(address), "buyer=0"
    old: address = self.buyer
    self.buyer = _buyer
    log BuyerUpdated(old_buyer=old, new_buyer=_buyer)


@external
def set_seller(_seller: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert self.status == STATUS_AWAITING_DEPOSIT, "already funded"
    assert _seller != empty(address), "seller=0"
    old: address = self.seller
    self.seller = _seller
    log SellerUpdated(old_seller=old, new_seller=_seller)


@external
def set_arbiter(_arbiter: address):
    assert msg.sender == self.arbiter, "only arbiter"
    assert _arbiter != empty(address), "arbiter=0"
    old: address = self.arbiter
    self.arbiter = _arbiter
    log ArbiterUpdated(old_arbiter=old, new_arbiter=_arbiter)
