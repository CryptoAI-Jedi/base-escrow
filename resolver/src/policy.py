from src.types import EscrowState, ResolutionDecision


def evaluate_policy(escrow: EscrowState) -> ResolutionDecision:
    """
    MVP policy aligned with Escrow.vy contract capabilities.

    DISPUTED -> REFUND: arbiter resolves dispute by refunding buyer.
    FUNDED   -> NONE:   waiting for buyer release or dispute; no auto-release
                        in MVP (contract has no deadline tracking on-chain).
    """
    if escrow.status == "DISPUTED":
        return ResolutionDecision("REFUND", "DISPUTED_ARBITER_REFUND", True)

    if escrow.status == "FUNDED":
        return ResolutionDecision("NONE", "FUNDED_AWAITING_PARTIES", False)

    return ResolutionDecision("NONE", "NO_ACTION", False)
