"""Evidence CID decoding and verification."""

import hashlib

import src.evidence as evidence_mod
from src.evidence import decode_cid_v1_raw_sha256, evidence_is_valid
from src.types import encode_reason_code
from tests.helpers import make_cid_v1_raw

CONTENT = b'{"order":"42","issue":"item not received"}'


def test_decode_valid_cid_roundtrip():
    cid = make_cid_v1_raw(CONTENT)
    assert cid.startswith("bafkrei")
    assert decode_cid_v1_raw_sha256(cid) == hashlib.sha256(CONTENT).digest()


def test_decode_rejects_dag_pb_cid():
    # CIDv1 dag-pb (0x70) — the common "bafybei..." format, not re-derivable here.
    assert decode_cid_v1_raw_sha256("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi") is None


def test_decode_rejects_garbage():
    assert decode_cid_v1_raw_sha256("") is None
    assert decode_cid_v1_raw_sha256("Qmfoo") is None  # CIDv0 (base58) unsupported
    assert decode_cid_v1_raw_sha256("b!!!notbase32!!!") is None


def test_evidence_valid_when_content_matches(monkeypatch):
    cid = make_cid_v1_raw(CONTENT)
    monkeypatch.setattr(evidence_mod, "fetch_evidence", lambda c: CONTENT)
    assert evidence_is_valid(cid) is True


def test_evidence_invalid_when_content_differs(monkeypatch):
    cid = make_cid_v1_raw(CONTENT)
    monkeypatch.setattr(evidence_mod, "fetch_evidence", lambda c: b"tampered")
    assert evidence_is_valid(cid) is False


def test_evidence_invalid_when_unfetchable(monkeypatch):
    cid = make_cid_v1_raw(CONTENT)

    def boom(c):
        raise OSError("gateway down")

    monkeypatch.setattr(evidence_mod, "fetch_evidence", boom)
    assert evidence_is_valid(cid) is False


def test_evidence_invalid_for_unsupported_cid_without_fetch(monkeypatch):
    def must_not_be_called(c):
        raise AssertionError("fetch_evidence must not run for undecodable CIDs")

    monkeypatch.setattr(evidence_mod, "fetch_evidence", must_not_be_called)
    assert evidence_is_valid("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi") is False


def test_encode_reason_code():
    encoded = encode_reason_code("AUTO_RELEASE_TIMEOUT")
    assert encoded.startswith("0x")
    assert len(encoded) == 66
    assert bytes.fromhex(encoded[2:]).rstrip(b"\x00") == b"AUTO_RELEASE_TIMEOUT"
