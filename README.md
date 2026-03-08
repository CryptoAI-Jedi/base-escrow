# Base Escrow — CRE-Powered Autonomous Dispute Resolution on Base

Base Escrow is a non-custodial escrow protocol on Base Sepolia where **Chainlink CRE autonomously monitors disputes and triggers on-chain resolution** without requiring a human arbiter to manually execute the final transaction.

> **Convergence: A Chainlink Hackathon submission**  
> Proposed track: **CRE & AI / Autonomous Agents**

## TL;DR

Traditional escrow and marketplace dispute handling is slow, manual, and trust-heavy. Base Escrow shows how a dispute can move from **on-chain event** to **CRE workflow** to **resolver decision** to **on-chain execution** in a transparent, verifiable loop.

## Project Highlights

- Role-gated escrow state machine in **Vyper** deployed on **Base Sepolia**
- **Chainlink CRE trigger** watches for `Disputed` events and dispatches a workflow
- **FastAPI resolver service** reads live contract state via `web3.py`, evaluates policy, and returns a signed decision
- CRE submits the resulting on-chain action autonomously
- Full demo path: **deposit → dispute → resolver decision → on-chain refund**
- Built as an **agent-ready dispute resolution architecture** for future AI-assisted commerce workflows

## Problem

Escrow is useful for marketplaces, services, and peer-to-peer commerce, but disputes usually require manual review and manual execution. That creates latency, cost, and trust assumptions. In Web3, that problem becomes even more visible because users want both automation and verifiable execution.

Base Escrow addresses this by combining:

- a simple escrow state machine,
- a CRE-triggered workflow,
- an external resolver service,
- and deterministic on-chain settlement.

The result is a workflow where a dispute can be detected and resolved programmatically, while the final outcome remains transparent and verifiable on-chain.

## Why this fits CRE & AI

Base Escrow fits the **CRE & AI** category because it demonstrates an **autonomous decision-and-execution loop** for a real Web3 workflow: a dispute event on-chain triggers a CRE workflow, the workflow calls an external resolver service that evaluates the escrow state and returns a machine-readable decision, and CRE then executes the corresponding on-chain action. In this MVP, the decision policy is deterministic for safety and auditability, but the resolver is intentionally designed as the decision layer where AI-assisted evidence summarization, recommendation generation, or dispute classification can be introduced without changing the verifiable execution path. This makes the project a practical example of **AI-in-the-loop architecture with verifiable on-chain execution**, rather than an unverifiable black-box automation demo.

## Architecture

```text
Buyer / Seller
    │ deposit() / mark_dispute()
    ▼
Escrow.vy (Base Sepolia)
    │ emits Disputed event
    ▼
CRE Trigger (cre/triggers/dispute_opened.trigger.yaml)
    │ dispatches workflow
    ▼
CRE Workflow (cre/workflows/dispute_resolution.workflow.yaml)
    │ POST /resolve
    ▼
Resolver API (FastAPI)
    │ reads chain state via web3.py
    │ evaluates policy
    │ returns action + should_submit_tx + reason_code
    ▼
CRE submits refund() or release() on-chain
    ▼
Escrow reaches final state
```

## Chainlink Integration

All Chainlink-related logic is linked below so judges can inspect the exact implementation.

### CRE Trigger

- [`cre/triggers/dispute_opened.trigger.yaml`](./cre/triggers/dispute_opened.trigger.yaml) — watches the deployed Escrow contract on Base Sepolia for the `Disputed` event and dispatches the workflow
- [`cre/triggers/deadline_scan.trigger.yaml`](./cre/triggers/deadline_scan.trigger.yaml) — periodic trigger scaffold for future time-based resolution and monitoring flows

### CRE Workflow

- [`cre/workflows/dispute_resolution.workflow.yaml`](./cre/workflows/dispute_resolution.workflow.yaml) — resolver call, execution gating, on-chain submission, and trace logging

### Resolver Service Consumed by CRE

- [`resolver/src/api.py`](./resolver/src/api.py) — `/resolve` endpoint used by CRE
- [`resolver/src/chain_client.py`](./resolver/src/chain_client.py) — contract reads/writes via `web3.py`
- [`resolver/src/policy.py`](./resolver/src/policy.py) — decision policy for escrow resolution
- [`resolver/src/config.py`](./resolver/src/config.py) — environment configuration
- [`resolver/src/types.py`](./resolver/src/types.py) — typed resolution payloads
- [`resolver/src/evidence.py`](./resolver/src/evidence.py) — evidence-related helper logic

### Reproduction / Demo Support

- [`HOW_TO_REPRODUCE.md`](./HOW_TO_REPRODUCE.md) — step-by-step setup and reproduction notes
- [`scripts/deploy.py`](./scripts/deploy.py) — deploy contract to Base Sepolia
- [`scripts/interact.py`](./scripts/interact.py) — deposit, dispute, release, refund, and status checks

## How it Works

1. Buyer funds the escrow.
2. Buyer or seller opens a dispute.
3. The contract emits a `Disputed` event.
4. A **Chainlink CRE trigger** detects the event.
5. The **CRE workflow** calls the resolver service.
6. The resolver reads the live contract state and evaluates the policy.
7. If the policy returns an executable action, CRE submits the transaction on-chain.
8. The workflow records the result and the escrow reaches its final state.

## Current Resolver Policy

For the MVP demo, the resolver uses a deliberately simple policy:

- `DISPUTED -> REFUND`
- `FUNDED -> NONE`

This was chosen to keep the execution path easy to audit and easy to verify in a hackathon setting.

## Live Demo Evidence

**Network:** Base Sepolia  
**Contract:** `0x6BA7B788322A703104f139aa0bA38D38048f7CE7`

| Step | Actor | Tx Hash | Result |
|---|---|---|---|
| Deploy | Arbiter | `0xae9b03591fc124236ada850e8ccb02116d63bc5a8492f86e64e5ca19b40e7784` | `AWAITING_DEPOSIT` |
| Deposit | Buyer | See [`README_test_evidence.md`](./README_test_evidence.md) | `FUNDED` |
| Dispute | Seller | `0xbbf8cbaca3183c4fb7bf6473feefb6a6ad5a219b7bf1cea72c98f79a2f78a428` | `DISPUTED` |
| CRE Resolver Refund | Resolver | `0x591b6f1de688ee436b42601d8256c473cc638a1b4a6c34429069efd168fe97ca` | `REFUNDED` |

Additional evidence: [`README_test_evidence.md`](./README_test_evidence.md)

## Decision Trace Format

The resolver returns a machine-readable decision object that CRE can consume and act on:

```json
{
  "action": "REFUND",
  "should_submit_tx": true,
  "reason_code": "DISPUTED_ARBITER_REFUND"
}
```

This design is important because it cleanly separates:

- **decision generation**,
- **execution gating**,
- and **verifiable on-chain settlement**.

That same interface can later support AI-generated recommendations without changing the downstream CRE execution path.

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contract | Vyper `0.4.3` |
| Network | Base Sepolia (`chainId: 84532`) |
| Workflow Engine | Chainlink Runtime Environment (CRE) |
| Resolver API | Python, FastAPI, Uvicorn |
| Chain Reads/Writes | `web3.py` |
| Config | `python-dotenv` |
| Wallet / RPC | EVM account + Base Sepolia RPC |

## Project Structure

```text
base-escrow/
├── contracts/
│   └── Escrow.vy
├── cre/
│   ├── triggers/
│   │   ├── dispute_opened.trigger.yaml
│   │   └── deadline_scan.trigger.yaml
│   └── workflows/
│       └── dispute_resolution.workflow.yaml
├── resolver/
│   ├── src/
│   │   ├── api.py
│   │   ├── chain_client.py
│   │   ├── policy.py
│   │   ├── config.py
│   │   ├── types.py
│   │   └── evidence.py
│   ├── abi/
│   │   └── Escrow.json
│   ├── config/
│   │   └── .env.example
│   └── requirements.txt
├── scripts/
│   ├── deploy.py
│   └── interact.py
├── out/
│   ├── Escrow.abi.json
│   └── Escrow.address.txt
├── switch-role.sh
└── HOW_TO_REPRODUCE.md
```

## State Machine

```text
AWAITING_DEPOSIT -> FUNDED -> RELEASED
                    -> DISPUTED -> REFUNDED
```

| Code | State |
|---|---|
| 0 | AWAITING_DEPOSIT |
| 1 | FUNDED |
| 2 | RELEASED |
| 3 | REFUNDED |
| 4 | DISPUTED |

## Role Permissions

| Role | Allowed Actions |
|---|---|
| Buyer | `deposit()`, `release()`, `mark_dispute()` |
| Seller | `mark_dispute()` |
| Arbiter / Resolver | `release()`, `approve_refund()`, `refund()` |

## Setup

### 1. Clone and install

```bash
git clone https://github.com/CryptoAI-Jedi/base-escrow.git
cd base-escrow
```

### 2. Contract scripts

```bash
pip install web3 vyper python-dotenv
```

Create role env files (`env.deploy`, `env.buyer`, `env.seller`, `env.arbiter`) as described in [`HOW_TO_REPRODUCE.md`](./HOW_TO_REPRODUCE.md).

### 3. Resolver service

```bash
cd resolver
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp config/.env.example config/.env
```

Then edit `config/.env` with your contract address, signer key, RPC endpoint, and resolver API token.

## Running the Resolver

### Start the API server

```bash
cd resolver
source .venv/bin/activate
uvicorn src.api:app --host 0.0.0.0 --port 8080 --reload
```

### Health check

```bash
curl http://127.0.0.1:8080/health
```

### Query resolution manually

```bash
curl -X POST http://127.0.0.1:8080/resolve \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <RESOLVER_API_TOKEN>" \
  -d '{"mode": "single", "escrow_id": "<ESCROW_CONTRACT_ADDRESS>"}'
```

### Run the batch resolver

```bash
cd resolver
source .venv/bin/activate
python -m src.main
```

## End-to-End Demo Flow

```bash
# 1. Deploy
cp env.deploy .env && python scripts/deploy.py

# 2. Buyer deposits
./switch-role.sh buyer
python scripts/interact.py deposit --eth 0.0001

# 3. Seller disputes
./switch-role.sh seller
python scripts/interact.py mark_dispute

# 4. CRE detects dispute and resolver returns executable decision
cd resolver && python -m src.main
# [CHAIN] refund tx=0x... status=1 reason=DISPUTED_ARBITER_REFUND

# 5. Verify final state
cd .. && python scripts/interact.py status
# status: REFUNDED | amount: 0 ETH
```

## Current Scope and Limitations

- Single-escrow-per-contract MVP
- Deterministic resolver policy in the current shipped demo
- Testnet deployment only
- Not audited for production or mainnet use
- No production evidence ingestion UI yet
- No reputation system, multi-party arbitration, or escrow factory yet

These constraints are intentional for the hackathon MVP: the goal is to prove the **autonomous CRE dispute resolution loop** end-to-end.

## Tested With

- Base Sepolia
- Vyper `0.4.3`
- Python 3.x
- FastAPI
- `web3.py`
- Chainlink CRE triggers and workflows

## Challenges

Key implementation challenges included:

- designing a clean state machine that remains easy to audit,
- wiring CRE triggers and workflows to a live dispute path,
- handling environment/config issues across contract scripts and resolver code,
- aligning resolver outputs with safe on-chain execution,
- and proving the full end-to-end flow with reproducible demo evidence.

## Security Notes

- Never commit private keys or `.env` files.
- Keep the resolver signer secure.
- Treat the resolver as a privileged execution component.
- This repository is for testnet demonstration and hackathon evaluation.

## Future Work

### 1. AI-assisted dispute reasoning

Introduce optional AI support for:

- evidence summarization,
- dispute classification,
- recommendation generation,
- and human-readable rationale creation.

The important design goal is that AI remains **advisory or assistive**, while the final execution path stays auditable and verifiable through CRE and on-chain settlement.

### 2. x402-paid resolver and arbitration services

Add **x402 payment capability** so autonomous agents or external clients can pay to access premium resolver features, such as:

- AI-assisted evidence analysis,
- priority dispute handling,
- policy simulation,
- or third-party arbitration-as-a-service.

This would allow Base Escrow to evolve into a machine-to-machine dispute infrastructure layer where agents can request paid decision support and CRE can still carry the result into verifiable on-chain execution.

### 3. Escrow factory and marketplace support

Expand from one-escrow-per-contract to:

- escrow factory deployment,
- marketplace order routing,
- multi-escrow indexing,
- and buyer/seller reputation primitives.

### 4. Hybrid policy engine

Support a tiered model:

- deterministic rules for safe default behavior,
- AI-assisted recommendations for ambiguous cases,
- and programmable policy modules for different marketplace verticals.

## License

MIT
