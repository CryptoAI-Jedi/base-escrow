"""
Chain client for EscrowMarket on Base.

Reads are authoritative: escrow discovery may come from the Ponder indexer,
but every escrow's state is re-read from the chain before a decision is made.

Transaction submission lives here ONLY as a development harness
(RESOLVER_SUBMIT_ENABLED=true). In production the CRE workflow owns
submission; the resolver is a pure decision service.
"""

import json
from pathlib import Path

from src.config import (
    ESCROW_MARKET_ADDRESS,
    RESOLVER_SIGNER_PRIVATE_KEY,
    RPC_URL,
    validate_chain_config,
)
from src.types import STATUS_MAP, EscrowState

_ACTIONABLE = {"FUNDED", "DISPUTED"}

# Bound for the no-indexer fallback scan (testnet scale).
_MAX_SCAN = 500


def _load_abi() -> list:
    candidates = [
        Path(__file__).parent.parent / "abi" / "EscrowMarket.json",
        Path(__file__).parent.parent.parent / "contracts" / "out" / "EscrowMarket.sol" / "EscrowMarket.json",
    ]
    for path in candidates:
        if path.exists():
            data = json.loads(path.read_text())
            return data["abi"] if isinstance(data, dict) else data
    raise FileNotFoundError("EscrowMarket ABI not found in resolver/abi/ or contracts/out/")


def _get_w3_and_contract():
    from web3 import Web3

    validate_chain_config()
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(ESCROW_MARKET_ADDRESS),
        abi=_load_abi(),
    )
    return w3, contract


def _to_state(escrow_id: int, raw) -> EscrowState:
    # getEscrow returns the IEscrowMarket.Escrow tuple in field order.
    (
        listing_id,
        buyer,
        seller,
        token,
        amount,
        fee_amount,
        status,
        release_deadline,
        seller_response_deadline,
        evidence_cid,
        disputed_by,
    ) = raw
    return EscrowState(
        escrow_id=escrow_id,
        status=STATUS_MAP.get(status, "UNKNOWN"),
        listing_id=listing_id,
        buyer=buyer,
        seller=seller,
        token=token,
        amount=amount,
        fee_amount=fee_amount,
        release_deadline_ts=release_deadline,
        seller_response_deadline_ts=seller_response_deadline,
        evidence_cid=evidence_cid,
        disputed_by=disputed_by if disputed_by != "0x0000000000000000000000000000000000000000" else None,
    )


def get_escrow(escrow_id: int) -> EscrowState | None:
    """Authoritative single-escrow read; None if the id doesn't exist."""
    _, contract = _get_w3_and_contract()
    raw = contract.functions.getEscrow(escrow_id).call()
    state = _to_state(escrow_id, raw)
    return None if state.status == "NONE" else state


def get_open_escrows(escrow_ids: list[int] | None = None) -> list[EscrowState]:
    """Read open (FUNDED/DISPUTED) escrows from the chain.

    `escrow_ids` normally comes from the Ponder indexer; when None, falls back
    to scanning ids 1..nextEscrowId-1 (bounded, testnet-scale).
    """
    try:
        validate_chain_config()
    except ValueError as e:
        print(f"[WARN] Config invalid, skipping chain read: {e}")
        return []

    try:
        _, contract = _get_w3_and_contract()

        if escrow_ids is None:
            next_id = contract.functions.nextEscrowId().call()
            start = max(1, next_id - _MAX_SCAN)
            escrow_ids = list(range(start, next_id))
            if start > 1:
                print(f"[WARN] Fallback scan truncated to ids {start}..{next_id - 1}")

        out: list[EscrowState] = []
        for escrow_id in escrow_ids:
            state = _to_state(escrow_id, contract.functions.getEscrow(escrow_id).call())
            if state.status in _ACTIONABLE:
                out.append(state)
        return out
    except Exception as e:
        print(f"[WARN] Contract read failed: {e}")
        return []


# ---------------------------------------------------------------------------
# Dev-only submission harness (production submission is owned by CRE)
# ---------------------------------------------------------------------------


def _submit(method: str, escrow_id: int, reason_code_hex: str) -> str:
    w3, contract = _get_w3_and_contract()
    account = w3.eth.account.from_key(RESOLVER_SIGNER_PRIVATE_KEY)

    fn = getattr(contract.functions, method)(escrow_id, bytes.fromhex(reason_code_hex[2:]))
    base_fee = w3.eth.get_block("latest")["baseFeePerGas"]
    priority = w3.to_wei(0.001, "gwei")
    tx = fn.build_transaction(
        {
            "from": account.address,
            "nonce": w3.eth.get_transaction_count(account.address),
            "maxPriorityFeePerGas": priority,
            "maxFeePerGas": base_fee * 2 + priority,
        }
    )
    signed = w3.eth.account.sign_transaction(tx, RESOLVER_SIGNER_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    print(f"[CHAIN] {method} escrow={escrow_id} tx={tx_hash.hex()} status={receipt.status}")
    return tx_hash.hex()


def submit_resolution(method: str, escrow_id: int, reason_code_hex: str) -> str:
    if method not in ("resolveRelease", "resolveRefund"):
        raise ValueError(f"Unknown resolution method: {method}")
    return _submit(method, escrow_id, reason_code_hex)
