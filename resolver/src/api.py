import secrets

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from src import config
from src.ai_assessor import assess_dispute
from src.chain_client import get_open_escrows
from src.indexer_client import get_open_escrow_ids
from src.policy import evaluate_policy

app = FastAPI()

try:
    from prometheus_fastapi_instrumentator import Instrumentator

    Instrumentator().instrument(app).expose(app)  # GET /metrics
except ImportError:
    print("[WARN] prometheus_fastapi_instrumentator not installed; /metrics disabled")


class ResolveRequest(BaseModel):
    mode: str  # "single" | "scan"
    escrow_id: int | None = None


def _decision_payload(escrow, decision) -> dict:
    payload = {
        "escrow_id": escrow.escrow_id,
        "action": decision.action,
        "reason_code": decision.reason_code,
        "should_submit_tx": decision.should_submit_tx,
        # Consumed verbatim by the CRE workflow's submit_tx step.
        "method": decision.method,
        "args": decision.args,
    }

    # AI-assisted assessment — advisory only, never overrides the policy decision
    ai_assessment = assess_dispute(escrow=escrow, decision=decision)
    if ai_assessment:
        payload["ai_assessment"] = ai_assessment
    return payload


@app.post("/resolve")
def resolve(req: ResolveRequest, authorization: str = Header(default="")):
    if not config.RESOLVER_API_TOKEN:
        raise HTTPException(status_code=500, detail="Server token not configured")
    if not secrets.compare_digest(authorization, f"Bearer {config.RESOLVER_API_TOKEN}"):
        raise HTTPException(status_code=401, detail="Unauthorized")

    # Discovery: prefer the indexer; fall back to a bounded on-chain scan.
    # Chain reads in get_open_escrows are authoritative either way.
    if req.mode == "single" and req.escrow_id is not None:
        escrow_ids = [req.escrow_id]
    else:
        try:
            escrow_ids = get_open_escrow_ids()
        except Exception as e:
            print(f"[WARN] Indexer unavailable, falling back to chain scan: {e}")
            escrow_ids = None

    escrows = get_open_escrows(escrow_ids)

    if not escrows:
        return {
            "escrow_id": req.escrow_id,
            "action": "NONE",
            "reason_code": "NO_ESCROW_FOUND",
            "should_submit_tx": False,
            "method": None,
            "args": {},
        }

    if req.mode == "single":
        escrow = escrows[0]
        return _decision_payload(escrow, evaluate_policy(escrow))

    # Scan mode: return every actionable decision (CRE iterates).
    decisions = [_decision_payload(e, evaluate_policy(e)) for e in escrows]
    actionable = [d for d in decisions if d["should_submit_tx"]]
    return {
        "mode": "scan",
        "count": len(decisions),
        "actionable": actionable,
        "decisions": decisions,
        # Top-level mirror of the first actionable decision so a simple CRE
        # workflow can submit one tx per scan tick without iterating.
        **(
            actionable[0]
            if actionable
            else {"action": "NONE", "reason_code": "NO_ACTION", "should_submit_tx": False}
        ),
    }


@app.get("/health")
def health():
    return {"status": "ok"}
