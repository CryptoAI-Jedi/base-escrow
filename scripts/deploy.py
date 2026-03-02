#!/usr/bin/env python3
import json
import os
from pathlib import Path

from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account
import vyper


def must_env(name: str) -> str:
    v = os.getenv(name, "").strip()
    if not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


def compile_vyper(contract_path: Path):
    source = contract_path.read_text(encoding="utf-8")
    out = vyper.compile_code(
        source,
        output_formats=["abi", "bytecode"],
    )
    return out["abi"], out["bytecode"]


def main():
    load_dotenv()

    rpc_url = must_env("RPC_URL")
    private_key = must_env("PRIVATE_KEY")
    chain_id = int(must_env("CHAIN_ID"))

    # constructor args
    buyer = Web3.to_checksum_address(must_env("BUYER_ADDRESS"))
    seller = Web3.to_checksum_address(must_env("SELLER_ADDRESS"))
    arbiter = Web3.to_checksum_address(must_env("ARBITER_ADDRESS"))

    w3 = Web3(Web3.HTTPProvider(rpc_url))
    if not w3.is_connected():
        raise RuntimeError("Web3 connection failed. Check RPC_URL.")

    acct = Account.from_key(private_key)
    deployer = Web3.to_checksum_address(acct.address)

    print(f"Connected: {w3.is_connected()}")
    print(f"Deployer:  {deployer}")
    print(f"Chain ID:  {chain_id}")
    print(f"Nonce:     {w3.eth.get_transaction_count(deployer)}")
    print(f"Balance:   {w3.from_wei(w3.eth.get_balance(deployer), 'ether')} ETH")

    contract_file = Path("contracts/Escrow.vy")
    abi, bytecode = compile_vyper(contract_file)

    Escrow = w3.eth.contract(abi=abi, bytecode=bytecode)
    tx = Escrow.constructor(buyer, seller, arbiter).build_transaction(
        {
            "from": deployer,
            "nonce": w3.eth.get_transaction_count(deployer),
            "chainId": chain_id,
            # EIP-1559
            "maxPriorityFeePerGas": w3.to_wei("1.5", "gwei"),
            "maxFeePerGas": w3.to_wei("3", "gwei"),
            "gas": 2_500_000,
        }
    )

    signed = w3.eth.account.sign_transaction(tx, private_key=private_key)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"Deploy tx sent: {tx_hash.hex()}")

    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
    if receipt.status != 1:
        raise RuntimeError("Deployment failed on-chain.")

    contract_address = receipt.contractAddress
    print(f"Escrow deployed at: {contract_address}")

    # Save artifacts
    out_dir = Path("out")
    out_dir.mkdir(exist_ok=True)
    (out_dir / "Escrow.abi.json").write_text(json.dumps(abi, indent=2), encoding="utf-8")
    (out_dir / "Escrow.address.txt").write_text(contract_address, encoding="utf-8")
    print("Saved: out/Escrow.abi.json and out/Escrow.address.txt")


if __name__ == "__main__":
    main()
