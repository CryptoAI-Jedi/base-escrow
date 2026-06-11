"""Table-driven tests for the deterministic policy engine."""

import pytest

import src.policy as policy_mod
from src.policy import evaluate_policy
from tests.helpers import make_escrow

DEADLINE = 1_000_000
RESPONSE_DEADLINE = 1_500_000


@pytest.fixture
def valid_evidence(monkeypatch):
    monkeypatch.setattr(policy_mod, "evidence_is_valid", lambda cid: True)


@pytest.fixture
def invalid_evidence(monkeypatch):
    monkeypatch.setattr(policy_mod, "evidence_is_valid", lambda cid: False)


# --- FUNDED ---------------------------------------------------------------


@pytest.mark.parametrize(
    "now,action,reason,submit",
    [
        (DEADLINE - 1, "NONE", "FUNDED_AWAITING_PARTIES", False),
        (DEADLINE, "NONE", "FUNDED_AWAITING_PARTIES", False),  # strict: not at the boundary
        (DEADLINE + 1, "RELEASE", "AUTO_RELEASE_TIMEOUT", True),
    ],
)
def test_funded_auto_release_boundary(now, action, reason, submit):
    escrow = make_escrow(status="FUNDED", release_deadline_ts=DEADLINE)
    decision = evaluate_policy(escrow, now=now)
    assert (decision.action, decision.reason_code, decision.should_submit_tx) == (action, reason, submit)


def test_funded_release_call_descriptor():
    escrow = make_escrow(status="FUNDED", release_deadline_ts=DEADLINE)
    decision = evaluate_policy(escrow, now=DEADLINE + 1)
    assert decision.method == "resolveRelease"
    assert decision.args["escrowId"] == escrow.escrow_id
    assert decision.args["reasonCode"].startswith("0x")
    assert len(decision.args["reasonCode"]) == 66  # bytes32 hex


# --- DISPUTED ---------------------------------------------------------------


def test_disputed_missing_evidence():
    escrow = make_escrow(status="DISPUTED", evidence_cid="", seller_response_deadline_ts=RESPONSE_DEADLINE)
    decision = evaluate_policy(escrow, now=RESPONSE_DEADLINE + 1)
    assert (decision.action, decision.reason_code) == ("HOLD", "MISSING_EVIDENCE")
    assert not decision.should_submit_tx


def test_disputed_invalid_evidence(invalid_evidence):
    escrow = make_escrow(
        status="DISPUTED", evidence_cid="bafkbogus", seller_response_deadline_ts=RESPONSE_DEADLINE
    )
    decision = evaluate_policy(escrow, now=RESPONSE_DEADLINE + 1)
    assert (decision.action, decision.reason_code) == ("HOLD", "EVIDENCE_HASH_MISMATCH")
    assert not decision.should_submit_tx


@pytest.mark.parametrize(
    "now,action,reason,submit",
    [
        (RESPONSE_DEADLINE - 1, "HOLD", "AWAITING_SELLER_RESPONSE", False),
        (RESPONSE_DEADLINE, "HOLD", "AWAITING_SELLER_RESPONSE", False),  # strict boundary
        (RESPONSE_DEADLINE + 1, "REFUND", "SELLER_INACTIVE_VALID_EVIDENCE", True),
    ],
)
def test_disputed_seller_inactive_boundary(valid_evidence, now, action, reason, submit):
    escrow = make_escrow(
        status="DISPUTED", evidence_cid="bafkvalid", seller_response_deadline_ts=RESPONSE_DEADLINE
    )
    decision = evaluate_policy(escrow, now=now)
    assert (decision.action, decision.reason_code, decision.should_submit_tx) == (action, reason, submit)


def test_disputed_refund_call_descriptor(valid_evidence):
    escrow = make_escrow(
        status="DISPUTED", evidence_cid="bafkvalid", seller_response_deadline_ts=RESPONSE_DEADLINE
    )
    decision = evaluate_policy(escrow, now=RESPONSE_DEADLINE + 1)
    assert decision.method == "resolveRefund"
    assert decision.args["escrowId"] == escrow.escrow_id


# --- terminal / default -----------------------------------------------------


@pytest.mark.parametrize("status", ["RELEASED", "REFUNDED", "NONE", "UNKNOWN"])
def test_terminal_states_no_action(status):
    decision = evaluate_policy(make_escrow(status=status), now=10**9)
    assert (decision.action, decision.reason_code, decision.should_submit_tx) == (
        "NONE",
        "NO_ACTION",
        False,
    )


def test_policy_never_submits_without_method():
    """Whenever should_submit_tx is True, the CRE call descriptor is complete."""
    for now in (0, DEADLINE + 1):
        decision = evaluate_policy(make_escrow(release_deadline_ts=DEADLINE), now=now)
        if decision.should_submit_tx:
            assert decision.method in ("resolveRelease", "resolveRefund")
            assert set(decision.args) == {"escrowId", "reasonCode"}
