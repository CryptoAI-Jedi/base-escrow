"""
Deterministic resolution policy.

Backed by on-chain deadline and evidence fields (EscrowMarket.sol), restoring
the original deadline/evidence rule table:

| Rule              | Condition                                            | Decision |
|-------------------|------------------------------------------------------|----------|
| Auto-release      | FUNDED and now > release_deadline                    | RELEASE  |
| Missing evidence  | DISPUTED and no evidence CID                         | HOLD     |
| Evidence invalid  | DISPUTED and CID unfetchable / content mismatch      | HOLD     |
| Seller inactive   | DISPUTED, valid evidence, now > seller response ddl  | REFUND   |
| Default           | none of the above                                    | NONE     |

The policy is the single authority on fund movement. The AI assessor is
advisory-only and never feeds back into this decision.
"""

import time

from src.evidence import evidence_is_valid
from src.types import EscrowState, ResolutionDecision, encode_reason_code


def _submit(escrow: EscrowState, action: str, reason: str) -> ResolutionDecision:
    method = "resolveRelease" if action == "RELEASE" else "resolveRefund"
    return ResolutionDecision(
        action=action,
        reason_code=reason,
        should_submit_tx=True,
        method=method,
        args={"escrowId": escrow.escrow_id, "reasonCode": encode_reason_code(reason)},
    )


def evaluate_policy(escrow: EscrowState, now: int | None = None) -> ResolutionDecision:
    now = int(time.time()) if now is None else now

    if escrow.status == "FUNDED":
        if now > escrow.release_deadline_ts:
            return _submit(escrow, "RELEASE", "AUTO_RELEASE_TIMEOUT")
        return ResolutionDecision("NONE", "FUNDED_AWAITING_PARTIES", False)

    if escrow.status == "DISPUTED":
        if not escrow.evidence_cid:
            return ResolutionDecision("HOLD", "MISSING_EVIDENCE", False)
        if not evidence_is_valid(escrow.evidence_cid):
            return ResolutionDecision("HOLD", "EVIDENCE_HASH_MISMATCH", False)
        if now > escrow.seller_response_deadline_ts:
            return _submit(escrow, "REFUND", "SELLER_INACTIVE_VALID_EVIDENCE")
        return ResolutionDecision("HOLD", "AWAITING_SELLER_RESPONSE", False)

    return ResolutionDecision("NONE", "NO_ACTION", False)
