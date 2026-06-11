"""API auth, response shape, and AI-assessor failure isolation."""

import pytest
from fastapi.testclient import TestClient

import src.api as api_mod
from src import config
from src.api import app
from src.types import ResolutionDecision
from tests.helpers import make_escrow

TOKEN = "test-token-123"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(config, "RESOLVER_API_TOKEN", TOKEN)
    # Isolate from chain/indexer/AI by default.
    monkeypatch.setattr(api_mod, "get_open_escrow_ids", lambda: [])
    monkeypatch.setattr(api_mod, "get_open_escrows", lambda ids=None: [])
    monkeypatch.setattr(api_mod, "assess_dispute", lambda **kw: None)
    return TestClient(app)


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_resolve_500_when_token_unconfigured(client, monkeypatch):
    monkeypatch.setattr(config, "RESOLVER_API_TOKEN", "")
    r = client.post("/resolve", json={"mode": "scan"}, headers=AUTH)
    assert r.status_code == 500


def test_resolve_401_wrong_token(client):
    r = client.post("/resolve", json={"mode": "scan"}, headers={"Authorization": "Bearer wrong"})
    assert r.status_code == 401


def test_resolve_401_missing_header(client):
    r = client.post("/resolve", json={"mode": "scan"})
    assert r.status_code == 401


def test_resolve_no_escrows(client):
    r = client.post("/resolve", json={"mode": "single", "escrow_id": 7}, headers=AUTH)
    assert r.status_code == 200
    body = r.json()
    assert body["action"] == "NONE"
    assert body["reason_code"] == "NO_ESCROW_FOUND"
    assert body["should_submit_tx"] is False


def test_resolve_single_actionable(client, monkeypatch):
    escrow = make_escrow(
        escrow_id=7,
        status="DISPUTED",
        evidence_cid="bafkvalid",
        seller_response_deadline_ts=100,
    )
    monkeypatch.setattr(api_mod, "get_open_escrows", lambda ids=None: [escrow])
    monkeypatch.setattr(
        api_mod,
        "evaluate_policy",
        lambda e: ResolutionDecision(
            "REFUND",
            "SELLER_INACTIVE_VALID_EVIDENCE",
            True,
            method="resolveRefund",
            args={"escrowId": 7, "reasonCode": "0x" + "00" * 32},
        ),
    )

    r = client.post("/resolve", json={"mode": "single", "escrow_id": 7}, headers=AUTH)
    body = r.json()
    assert body["escrow_id"] == 7
    assert body["should_submit_tx"] is True
    # The CRE workflow consumes these verbatim:
    assert body["method"] == "resolveRefund"
    assert body["args"]["escrowId"] == 7
    assert "ai_assessment" not in body  # assessor disabled -> key omitted


def test_resolve_scan_mode_lists_decisions(client, monkeypatch):
    open_escrows = [
        make_escrow(escrow_id=1, status="FUNDED", release_deadline_ts=10**12),
        make_escrow(escrow_id=2, status="FUNDED", release_deadline_ts=1),
    ]
    monkeypatch.setattr(api_mod, "get_open_escrow_ids", lambda: [1, 2])
    monkeypatch.setattr(api_mod, "get_open_escrows", lambda ids=None: open_escrows)

    r = client.post("/resolve", json={"mode": "scan"}, headers=AUTH)
    body = r.json()
    assert body["count"] == 2
    assert len(body["actionable"]) == 1
    assert body["actionable"][0]["escrow_id"] == 2
    # Top-level mirror of the first actionable decision:
    assert body["should_submit_tx"] is True
    assert body["method"] == "resolveRelease"


def test_resolve_falls_back_to_chain_scan_when_indexer_down(client, monkeypatch):
    seen = {}

    def indexer_down():
        raise RuntimeError("indexer offline")

    def fake_get_open_escrows(ids=None):
        seen["ids"] = ids
        return []

    monkeypatch.setattr(api_mod, "get_open_escrow_ids", indexer_down)
    monkeypatch.setattr(api_mod, "get_open_escrows", fake_get_open_escrows)

    r = client.post("/resolve", json={"mode": "scan"}, headers=AUTH)
    assert r.status_code == 200
    assert seen["ids"] is None  # None signals the bounded on-chain fallback scan


def test_ai_assessor_failure_is_isolated(client, monkeypatch):
    """An exploding AI layer must never break the policy response."""
    escrow = make_escrow(escrow_id=3, status="FUNDED", release_deadline_ts=1)
    monkeypatch.setattr(api_mod, "get_open_escrows", lambda ids=None: [escrow])

    import src.ai_assessor as ai_mod

    class ExplodingClient:
        def __init__(self, api_key):
            raise RuntimeError("anthropic down")

    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
    monkeypatch.setattr(api_mod, "assess_dispute", ai_mod.assess_dispute)
    monkeypatch.setattr(
        "anthropic.Anthropic", ExplodingClient, raising=False
    ) if _has_anthropic() else None

    r = client.post("/resolve", json={"mode": "single", "escrow_id": 3}, headers=AUTH)
    body = r.json()
    assert r.status_code == 200
    assert body["action"] == "RELEASE"
    assert "ai_assessment" not in body


def _has_anthropic() -> bool:
    try:
        import anthropic  # noqa: F401

        return True
    except ImportError:
        return False
