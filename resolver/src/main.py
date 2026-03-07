from src.chain_client import get_open_escrows, submit_release, submit_refund
from src.policy import evaluate_policy

def run_once():
    escrows = get_open_escrows()
    for e in escrows:
        decision = evaluate_policy(e)

        if decision.action == "RELEASE" and decision.should_submit_tx:
            tx = submit_release(e.escrow_id, decision.reason_code)
            print(f"[RESOLVED] escrow={e.escrow_id} action=RELEASE reason={decision.reason_code} tx={tx}")

        elif decision.action == "REFUND" and decision.should_submit_tx:
            tx = submit_refund(e.escrow_id, decision.reason_code)
            print(f"[RESOLVED] escrow={e.escrow_id} action=REFUND reason={decision.reason_code} tx={tx}")

        else:
            print(f"[SKIP] escrow={e.escrow_id} action={decision.action} reason={decision.reason_code}")

if __name__ == "__main__":
    run_once()