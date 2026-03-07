"""
Chain client for reading escrow state and submitting transactions on Base.
"""
import json
from pathlib import Path
from typing import List

from src.config import (
    RPC_URL,
    ESCROW_CONTRACT_ADDRESS,
    RESOLVER_SIGNER_PRIVATE_KEY,
    validate_chain_config,
)
from src.types import EscrowState

_STATUS_MAP = {
    0: "AWAITING_DEPOSIT",
    1: "FUNDED",
    2: "RELEASED",
    3: "REFUNDED",
    4: "DISPUTED",
}

# Actionable states — ignore terminal/pre-funded states
_ACTIONABLE = {"FUNDED", "DISPUTED"}


def _load_abi() -> list:
    candidates = [
        Path(__file__).parent.parent / "abi" / "Escrow.json",
        Path(__file__).parent.parent.parent / "out" / "Escrow.abi.json",
    ]
    for path in candidates:
        if path.exists():
            return json.loads(path.read_text())
    raise FileNotFoundError("Escrow ABI not found in resolver/abi/ or out/")


def _get_w3_and_contract():
    from web3 import Web3
    validate_chain_config()
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    abi = _load_abi()
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(ESCROW_CONTRACT_ADDRESS),
        abi=abi,
    )
    return w3, contract


def get_open_escrows() -> List[EscrowState]:
    """Read current state from the deployed escrow contract."""
    try:
        validate_chain_config()
    except ValueError as e:
        print(f"[WARN] Config invalid, skipping chain read: {e}")
        return []

    try:
        w3, contract = _get_w3_and_contract()
        status_int = contract.functions.status().call()
        status_str = _STATUS_MAP.get(status_int, "UNKNOWN")

        if status_str not in _ACTIONABLE:
            print(f"[INFO] Escrow status={status_str}, no action needed")
            return []

        buyer = contract.functions.buyer().call()
        seller = contract.functions.seller().call()

        return [
            EscrowState(
                escrow_id=ESCROW_CONTRACT_ADDRESS,
                status=status_str,
                buyer=buyer,
                seller=seller,
            )
        ]
    except Exception as e:
        print(f"[WARN] Contract read failed: {e}")
        return []


def submit_release(escrow_id: str, reason_code: str) -> str:
    """Call release() on the escrow contract as arbiter."""
    w3, contract = _get_w3_and_contract()
    account = w3.eth.account.from_key(RESOLVER_SIGNER_PRIVATE_KEY)
    tx = contract.functions.release().build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 100_000,
        "gasPrice": w3.eth.gas_price,
    })
    signed = w3.eth.account.sign_transaction(tx, RESOLVER_SIGNER_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    print(f"[CHAIN] release tx={tx_hash.hex()} status={receipt.status} reason={reason_code}")
    return tx_hash.hex()


def submit_refund(escrow_id: str, reason_code: str) -> str:
    """Call refund() on the escrow contract as arbiter (status must be DISPUTED)."""
    w3, contract = _get_w3_and_contract()
    account = w3.eth.account.from_key(RESOLVER_SIGNER_PRIVATE_KEY)
    tx = contract.functions.refund().build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 100_000,
        "gasPrice": w3.eth.gas_price,
    })
    signed = w3.eth.account.sign_transaction(tx, RESOLVER_SIGNER_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    print(f"[CHAIN] refund tx={tx_hash.hex()} status={receipt.status} reason={reason_code}")
    return tx_hash.hex()
