"""
Ponder GraphQL client — escrow DISCOVERY only.

The indexer is a hint for which escrows to look at; every decision re-verifies
state directly on-chain (chain_client) before any transaction is proposed.
"""

import requests

from src.config import PONDER_GRAPHQL_URL

_OPEN_ESCROWS_QUERY = """
query OpenEscrows {
  escrows(where: { status_in: ["FUNDED", "DISPUTED"] }, limit: 500) {
    items { id }
  }
}
"""


def get_open_escrow_ids(timeout: int = 10) -> list[int]:
    """Return ids of escrows the indexer believes are open (FUNDED/DISPUTED).

    Raises on transport/shape errors so callers can fall back to an on-chain
    scan.
    """
    r = requests.post(
        PONDER_GRAPHQL_URL,
        json={"query": _OPEN_ESCROWS_QUERY},
        timeout=timeout,
    )
    r.raise_for_status()
    payload = r.json()
    if "errors" in payload:
        raise RuntimeError(f"Ponder GraphQL errors: {payload['errors']}")
    items = payload["data"]["escrows"]["items"]
    return [int(item["id"]) for item in items]
