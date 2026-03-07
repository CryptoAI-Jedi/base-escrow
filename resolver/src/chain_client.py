import os
from typing import List
from dotenv import load_dotenv
from src.types import EscrowState

load_dotenv("resolver/config/.env", override=False)
load_dotenv("resolver/config/.env.example", override=False)

RPC_URL = os.getenv("RPC_URL", "")
CHAIN_ID = int(os.getenv("CHAIN_ID", "84532"))
ESCROW_CONTRACT_ADDRESS = os.getenv("ESCROW_CONTRACT_ADDRESS", "")
RESOLVER_SIGNER_ADDRESS = os.getenv("RESOLVER_SIGNER_ADDRESS", "")

def get_open_escrows() -> List[EscrowState]:
    """
    TODO: Replace with real Base contract reads.
    For now returns empty list so the loop runs safely.
    """
    return []

def submit_release(escrow_id: str, reason_code: str) -> str:
    """
    TODO: Replace with ethers/web3 tx call to contract.resolveRelease(...)
    """
    return f"0xmock_release_tx_{escrow_id}_{reason_code}"

def submit_refund(escrow_id: str, reason_code: str) -> str:
    """
    TODO: Replace with ethers/web3 tx call to contract.resolveRefund(...)
    """
    return f"0xmock_refund_tx_{escrow_id}_{reason_code}"