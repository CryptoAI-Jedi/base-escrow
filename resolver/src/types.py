from dataclasses import dataclass, field

# Mirrors IEscrowMarket.EscrowStatus
STATUS_MAP = {
    0: "NONE",
    1: "FUNDED",
    2: "DISPUTED",
    3: "RELEASED",
    4: "REFUNDED",
}


@dataclass
class EscrowState:
    escrow_id: int
    status: str  # FUNDED, DISPUTED, RELEASED, REFUNDED
    listing_id: int
    buyer: str
    seller: str
    token: str  # 0x0 = native ETH
    amount: int  # wei / token base units
    fee_amount: int
    release_deadline_ts: int
    seller_response_deadline_ts: int  # 0 until a dispute opens
    evidence_cid: str  # "" if none
    disputed_by: str | None = None


@dataclass
class ResolutionDecision:
    action: str  # RELEASE, REFUND, HOLD, NONE
    reason_code: str
    should_submit_tx: bool
    # Contract call descriptor consumed verbatim by the CRE workflow's
    # submit_tx step (None unless should_submit_tx is True).
    method: str | None = None  # "resolveRelease" | "resolveRefund"
    args: dict = field(default_factory=dict)  # {"escrowId": ..., "reasonCode": "0x..."}


def encode_reason_code(reason: str) -> str:
    """ASCII reason code -> right-padded bytes32 hex for the contract call."""
    raw = reason.encode("ascii")[:32]
    return "0x" + raw.ljust(32, b"\x00").hex()
