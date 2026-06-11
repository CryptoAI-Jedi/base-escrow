"""
Evidence verification against IPFS CID commitments.

The on-chain `evidenceCID` is content-addressed, so the CID itself is the
integrity commitment: we fetch the bytes from an IPFS gateway and recompute
the CID locally before trusting the content.

Convention: evidence is uploaded as a single raw block, CIDv1 / raw codec /
sha2-256 (base32 "bafkr..." CIDs — Pinata: `cidVersion: 1` with raw leaves;
the web app's upload helper enforces this). Other CID formats (e.g. dag-pb
"bafyb...") cannot be re-derived without a full UnixFS implementation, so
they are treated as UNVERIFIED and the policy holds the escrow.
"""

import base64
import hashlib

import requests

from src.config import IPFS_GATEWAY_URL

_CID_RAW_SHA256_PREFIX = bytes([0x01, 0x55, 0x12, 0x20])  # CIDv1, raw, sha2-256, 32 bytes


def decode_cid_v1_raw_sha256(cid: str) -> bytes | None:
    """Return the 32-byte sha256 digest committed by a CIDv1/raw/sha2-256 CID,
    or None if the CID is not in that format."""
    if not cid or cid[0] != "b":  # multibase prefix: base32 lowercase
        return None
    body = cid[1:].upper()
    body += "=" * (-len(body) % 8)
    try:
        raw = base64.b32decode(body)
    except Exception:
        return None
    if len(raw) != 36 or not raw.startswith(_CID_RAW_SHA256_PREFIX):
        return None
    return raw[4:]


def fetch_evidence(cid: str, timeout: int = 10) -> bytes:
    url = f"{IPFS_GATEWAY_URL.rstrip('/')}/ipfs/{cid}"
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.content


def evidence_is_valid(cid: str) -> bool:
    """Fetch evidence content and verify it re-hashes to the committed CID."""
    digest = decode_cid_v1_raw_sha256(cid)
    if digest is None:
        return False  # unsupported/garbled CID format -> unverifiable
    try:
        content = fetch_evidence(cid)
    except Exception:
        return False  # unfetchable -> unverifiable
    return hashlib.sha256(content).digest() == digest
