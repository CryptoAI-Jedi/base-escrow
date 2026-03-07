import time
from src.types import EscrowState, ResolutionDecision
from src.evidence import evidence_hash_matches

def evaluate_policy(escrow: EscrowState) -> ResolutionDecision:
    now = int(time.time())

    # Rule 1: auto-release timeout
    if escrow.status == "FUNDED" and now > escrow.release_deadline_ts:
        return ResolutionDecision("RELEASE", "AUTO_RELEASE_TIMEOUT", True)

    # Disputed path
    if escrow.status == "DISPUTED":
        if not escrow.evidence_uri or not escrow.evidence_hash:
            return ResolutionDecision("HOLD", "MISSING_EVIDENCE", False)

        valid = evidence_hash_matches(escrow.evidence_uri, escrow.evidence_hash)
        if not valid:
            return ResolutionDecision("HOLD", "EVIDENCE_HASH_MISMATCH", False)

        if now > escrow.seller_response_deadline_ts:
            return ResolutionDecision("REFUND", "SELLER_INACTIVE_VALID_EVIDENCE", True)

    return ResolutionDecision("NONE", "NO_ACTION", False)