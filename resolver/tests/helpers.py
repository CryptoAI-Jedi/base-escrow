import base64
import hashlib

from src.types import EscrowState

ZERO = "0x0000000000000000000000000000000000000000"


def make_cid_v1_raw(content: bytes) -> str:
    """Build the CIDv1/raw/sha2-256 CID for given content (the evidence
    upload convention)."""
    digest = hashlib.sha256(content).digest()
    raw = bytes([0x01, 0x55, 0x12, 0x20]) + digest
    return "b" + base64.b32encode(raw).decode().lower().rstrip("=")


def make_escrow(**overrides) -> EscrowState:
    defaults = dict(
        escrow_id=1,
        status="FUNDED",
        listing_id=1,
        buyer="0x45FEB305467ee1130Ae6049B4a4C8B798Fa2d2B4",
        seller="0x6A18650859bb60631C940C03353C8EE9554A3790",
        token=ZERO,
        amount=10**15,
        fee_amount=0,
        release_deadline_ts=1_000_000,
        seller_response_deadline_ts=0,
        evidence_cid="",
        disputed_by=None,
    )
    defaults.update(overrides)
    return EscrowState(**defaults)
