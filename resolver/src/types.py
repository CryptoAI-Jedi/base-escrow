from dataclasses import dataclass, field
from typing import Optional

@dataclass
class EscrowState:
    escrow_id: str
    status: str  # FUNDED, DISPUTED, RELEASED, REFUNDED
    buyer: str
    seller: str
    evidence_uri: Optional[str] = None
    evidence_hash: Optional[str] = None
    release_deadline_ts: int = 0
    seller_response_deadline_ts: int = 0
    disputed_at_ts: Optional[int] = None

@dataclass
class ResolutionDecision:
    action: str  # RELEASE, REFUND, HOLD, NONE
    reason_code: str
    should_submit_tx: bool