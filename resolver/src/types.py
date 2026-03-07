from dataclasses import dataclass
from typing import Optional

@dataclass
class EscrowState:
    escrow_id: str
    status: str  # FUNDED, DISPUTED, RELEASED, REFUNDED
    buyer: str
    seller: str
    evidence_uri: Optional[str]
    evidence_hash: Optional[str]
    release_deadline_ts: int
    seller_response_deadline_ts: int
    disputed_at_ts: Optional[int]

@dataclass
class ResolutionDecision:
    action: str  # RELEASE, REFUND, HOLD, NONE
    reason_code: str
    should_submit_tx: bool