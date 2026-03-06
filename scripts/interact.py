#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

from dotenv import load_dotenv
from eth_account import Account
from web3 import Web3


def must_env(name: str) -> str:
    v = os.getenv(name, "").strip()
    if not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


def load_contract(w3: Web3):
    abi_path = Path("out/Escrow.abi.json")
    addr_path = Path("out/Escrow.address.txt")

    if not abi_path.exists():
        raise RuntimeError("Missing out/Escrow.abi.json")
    if not addr_path.exists():
        raise RuntimeError("Missing out/Escrow.address.txt")

    abi = json.loads(abi_path.read_text(encoding="utf-8"))
    address = Web3.to_checksum_address(addr_path.read_text(encoding="utf-8").strip())
    return w3.eth.contract(address=address, abi=abi), address


def fee_params(w3: Web3):
    base = w3.eth.gas_price
    priority = w3.to_wei("1.5", "gwei")
    max_fee = int(base * 2 + priority)
    return priority, max_fee


def send_tx(w3: Web3, acct, tx_builder, value_wei: int = 0):
    nonce = w3.eth.get_transaction_count(acct.address)
    max_priority, max_fee = fee_params(w3)

    tx = tx_builder.build_transaction(
        {
            "from": acct.address,
            "nonce": nonce,
            "chainId": int(must_env("CHAIN_ID")),
            "value": value_wei,
            "maxPriorityFeePerGas": max_priority,
            "maxFeePerGas": max_fee,
            "gas": 500_000,
        }
    )

    signed = w3.eth.account.sign_transaction(tx, private_key=must_env("PRIVATE_KEY"))
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"tx_hash: {tx_hash.hex()}")

    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
    print(f"status: {receipt.status} | block: {receipt.blockNumber}")
    if receipt.status != 1:
        raise RuntimeError("Transaction reverted")
    return receipt


def show_status(w3: Web3, c):
    status_map = {
        0: "AWAITING_DEPOSIT",
        1: "FUNDED",
        2: "RELEASED",
        3: "REFUNDED",
        4: "DISPUTED",
    }

    buyer = c.functions.buyer().call()
    seller = c.functions.seller().call()
    arbiter = c.functions.arbiter().call()
    amount = c.functions.amount().call()
    status = c.functions.status().call()

    print(f"buyer:   {buyer}")
    print(f"seller:  {seller}")
    print(f"arbiter: {arbiter}")
    print(f"amount:  {w3.from_wei(amount, 'ether')} ETH ({amount} wei)")
    print(f"status:  {status_map.get(status, f'UNKNOWN({status})')}")


def main():
    parser = argparse.ArgumentParser(description="Escrow interaction CLI")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_dep = sub.add_parser("deposit", help="Call deposit()")
    p_dep.add_argument("--eth", required=True, type=float, help="ETH amount to deposit")

    sub.add_parser("release", help="Call release()")
    sub.add_parser("mark_dispute", help="Call mark_dispute()")
    sub.add_parser("approve_refund", help="Call approve_refund()")
    sub.add_parser("refund", help="Call refund()")
    sub.add_parser("status", help="Read on-chain escrow state")

    args = parser.parse_args()
    load_dotenv()

    w3 = Web3(Web3.HTTPProvider(must_env("RPC_URL")))
    if not w3.is_connected():
        raise RuntimeError("Web3 connection failed. Check RPC_URL.")

    acct = Account.from_key(must_env("PRIVATE_KEY"))
    contract, address = load_contract(w3)

    print(f"contract: {address}")
    print(f"sender:   {acct.address}")

    if args.cmd == "status":
        show_status(w3, contract)
        return

    if args.cmd == "deposit":
        value_wei = w3.to_wei(args.eth, "ether")
        send_tx(w3, acct, contract.functions.deposit(), value_wei=value_wei)
    elif args.cmd == "release":
        send_tx(w3, acct, contract.functions.release())
    elif args.cmd == "mark_dispute":
        send_tx(w3, acct, contract.functions.mark_dispute())
    elif args.cmd == "approve_refund":
        send_tx(w3, acct, contract.functions.approve_refund())
    elif args.cmd == "refund":
        send_tx(w3, acct, contract.functions.refund())

    print("\nPost-tx state:")
    show_status(w3, contract)


if __name__ == "__main__":
    main()