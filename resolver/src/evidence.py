import hashlib
import json
import requests

def canonical_json_hash(payload: dict) -> str:
    canonical = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

def fetch_evidence_json(uri: str) -> dict:
    if uri.startswith("http://") or uri.startswith("https://"):
        r = requests.get(uri, timeout=10)
        r.raise_for_status()
        return r.json()
    with open(uri, "r", encoding="utf-8") as f:
        return json.load(f)

def evidence_hash_matches(uri: str, onchain_hash: str) -> bool:
    payload = fetch_evidence_json(uri)
    return canonical_json_hash(payload) == onchain_hash