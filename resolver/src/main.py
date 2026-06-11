"""
Standalone batch loop — DEVELOPMENT HARNESS ONLY.

In production, the CRE workflow owns transaction submission and this module
must not run with submission enabled. Submission is gated behind
RESOLVER_SUBMIT_ENABLED (default: false), in which case this loop only prints
the decisions it would have submitted.
"""

from src.chain_client import get_open_escrows, submit_resolution
from src.config import RESOLVER_SUBMIT_ENABLED
from src.indexer_client import get_open_escrow_ids
from src.policy import evaluate_policy


def run_once():
    try:
        escrow_ids = get_open_escrow_ids()
    except Exception as e:
        print(f"[WARN] Indexer unavailable, falling back to chain scan: {e}")
        escrow_ids = None

    escrows = get_open_escrows(escrow_ids)
    if not escrows:
        print("[SCAN] no open escrows")
        return

    for escrow in escrows:
        decision = evaluate_policy(escrow)

        if not decision.should_submit_tx:
            print(
                f"[SKIP] escrow={escrow.escrow_id} action={decision.action} "
                f"reason={decision.reason_code}"
            )
            continue

        if not RESOLVER_SUBMIT_ENABLED:
            print(
                f"[DRY-RUN] escrow={escrow.escrow_id} would submit "
                f"{decision.method}({decision.args}) reason={decision.reason_code} "
                "(set RESOLVER_SUBMIT_ENABLED=true to submit — dev only, CRE owns production submission)"
            )
            continue

        tx = submit_resolution(decision.method, escrow.escrow_id, decision.args["reasonCode"])
        print(
            f"[RESOLVED] escrow={escrow.escrow_id} action={decision.action} "
            f"reason={decision.reason_code} tx={tx}"
        )


if __name__ == "__main__":
    run_once()
