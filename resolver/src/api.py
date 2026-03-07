import os
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from src.chain_client import get_open_escrows
from src.policy import evaluate_policy

app = FastAPI()
API_TOKEN = os.getenv("RESOLVER_API_TOKEN", "")

class ResolveRequest(BaseModel):
    mode: str
    escrow_id: str | None = None

@app.post("/resolve")
def resolve(req: ResolveRequest, authorization: str = Header(default="")):
    if not API_TOKEN:
        raise HTTPException(status_code=500, detail="Server token not configured")
    if authorization != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")

    escrows = get_open_escrows()

    if req.mode == "single" and req.escrow_id:
        escrows = [e for e in escrows if e.escrow_id == req.escrow_id]

    if not escrows:
        return {
            "escrow_id": req.escrow_id or "",
            "action": "NONE",
            "reason_code": "NO_ESCROW_FOUND",
            "should_submit_tx": False
        }

    # MVP: resolve first matching escrow
    e = escrows[0]
    d = evaluate_policy(e)
    return {
        "escrow_id": e.escrow_id,
        "action": d.action,
        "reason_code": d.reason_code,
        "should_submit_tx": d.should_submit_tx
    }

@app.get("/health")
def health():
    return {"status": "ok"}