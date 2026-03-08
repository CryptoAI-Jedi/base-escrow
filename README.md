# Base Escrow — CRE-Powered Dispute Resolution on Base

A non-custodial escrow protocol on Base Sepolia where **Chainlink CRE autonomously monitors disputes and triggers on-chain resolution** without manual arbiter intervention.

> **Convergence: A Chainlink Hackathon submission** — Track: CRE & AI / Autonomous Agents

---

## Project Highlights

- Role-gated escrow state machine in **Vyper** deployed on Base Sepolia
- **Chainlink CRE** event trigger watches for `Disputed` events and dispatches a resolution workflow
- **FastAPI resolver service** reads live contract state via web3.py, evaluates a deterministic policy, and returns a signed decision (`REFUND` or `RELEASE`)
- Resolver submits the on-chain transaction autonomously — no human arbiter action required
- Full end-to-end demo: deposit → dispute → CRE resolver → confirmed refund tx on-chain

---

## Architecture (Contract + Resolver + CRE)

This repo implements a deterministic dispute-resolution pipeline on Base Sepolia:

1. **Escrow Smart Contract (`contracts/Escrow.vy`)**
   - Single escrow per contract instance
   - Role-gated actions:
     - Buyer: `deposit()`, `release()`
     - Seller/Buyer: `mark_dispute()`
     - Arbiter: `approve_refund()`, `refund()`
   - State machine:
     - `AWAITING_DEPOSIT -> FUNDED -> RELEASED`
     - `FUNDED -> DISPUTED -> REFUNDED` (via arbiter path)

2. **Resolver API (`resolver/src/api.py`)**
   - `GET /health` for liveness
   - `POST /resolve` for policy decisions
   - Returns deterministic decision payload:
     - `action`
     - `reason_code`
     - `should_submit_tx`

3. **Policy Engine (`resolver/src/policy.py`)**
   - Maps on-chain state to explicit, reason-coded outcomes
   - Current MVP policy:
     - `DISPUTED -> REFUND`
     - `FUNDED -> NONE`

4. **Chain Client (`resolver/src/chain_client.py`)**
   - Reads escrow state directly from Base Sepolia
   - Submits `release()` / `refund()` transactions using the configured signer key

5. **CRE Integration (`cre/triggers`, `cre/workflows`)**
   - Trigger listens for a dispute-opened signal
   - Workflow calls resolver API, evaluates a guard, and submits the on-chain transaction

## Decision Trace Format (Example)

```json
{
  "escrow_id": "0x...",
  "action": "REFUND",
  "reason_code": "DISPUTED_ARBITER_REFUND",
  "should_submit_tx": true
}
```

## Current Scope & Limitations (MVP)

- **Single-escrow instance model** (one escrow per deployed contract), not yet a multi-listing marketplace factory
- **Testnet only** (Base Sepolia); not audited for mainnet use
- **Evidence handling is hash/URI-oriented in workflow design**; full evidence arbitration UX is out of current scope

## Demo Evidence

- Reproducible setup/runbook: [`HOW_TO_REPRODUCE.md`](./HOW_TO_REPRODUCE.md)
- Test evidence log: [`README_test_evidence.md`](./README_test_evidence.md)
- Latest deployed contract address artifact: [`out/Escrow.address.txt`](./out/Escrow.address.txt)
- Demo video (3–5 min): **[Add Loom URL here after recording]**

## Tested With

- Python 3.12
- Vyper 0.4.3
- Web3.py
- FastAPI
- Uvicorn
- Base Sepolia (`chainId=84532`)

---

## Chainlink CRE Integration

All CRE-related files are in the [`cre/`](./cre/) directory.

### Trigger — [`cre/triggers/dispute_opened.trigger.yaml`](./cre/triggers/dispute_opened.trigger.yaml)

Watches the deployed Escrow contract on Base Sepolia for the `Disputed` event. When a dispute is opened, dispatches the resolution workflow with the contract address as the escrow identifier.

### Workflow — [`cre/workflows/dispute_resolution.workflow.yaml`](./cre/workflows/dispute_resolution.workflow.yaml)

1. **`resolve` step** — HTTP POST to the resolver API (`/resolve`) with the escrow ID
2. **`guard_action` step** — conditional gate: only proceeds if `should_submit_tx == true`
3. **`submit_tx` step** — CRE submits the `RELEASE` or `REFUND` transaction on-chain
4. **`trace` step** — logs the resolution result with tx hash and reason code

### Resolver Service — [`resolver/`](./resolver/)

FastAPI service that acts as the "brain" for CRE:
- `src/api.py` — `/resolve` endpoint (bearer auth, returns resolution decision)
- `src/chain_client.py` — reads escrow state from Base via web3.py; submits `release()` / `refund()` txs
- `src/policy.py` — deterministic policy: `DISPUTED → REFUND`, `FUNDED → NONE`
- `src/config.py` — env-based config with absolute path resolution (works regardless of CWD)

### Live Demo Evidence

Contract: `0x6BA7B788322A703104f139aa0bA38D38048f7CE7` (Base Sepolia)

| Step | Actor | Tx Hash | Result |
|---|---|---|---|
| Deploy | Arbiter | `0xae9b03591fc124236ada850e8ccb02116d63bc5a8492f86e64e5ca19b40e7784` | `AWAITING_DEPOSIT` |
| Deposit | Buyer | *(see README_test_evidence.md)* | `FUNDED` |
| Dispute | Seller | `0xbbf8cbaca3183c4fb7bf6473feefb6a6ad5a219b7bf1cea72c98f79a2f78a428` | `DISPUTED` |
| CRE Resolver Refund | Resolver | `0x591b6f1de688ee436b42601d8256c473cc638a1b4a6c34429069efd168fe97ca` | `REFUNDED` |

Full evidence: [README_test_evidence.md](./README_test_evidence.md)

---

## Architecture Overview

```text
Buyer/Seller
    │ deposit() / mark_dispute()
    ▼
Escrow.vy (Base Sepolia)
    │ emits Disputed event
    ▼
CRE Trigger (dispute_opened.trigger.yaml)
    │ dispatches workflow
    ▼
CRE Workflow (dispute_resolution.workflow.yaml)
    │ HTTP POST /resolve
    ▼
Resolver API (FastAPI)
    │ reads chain state via web3.py
    │ evaluates policy
    │ returns { action: REFUND, should_submit_tx: true }
    ▼
CRE submits refund() on-chain
    ▼
Escrow state → REFUNDED
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contract | Vyper `0.4.3` |
| Network | Base Sepolia (`chainId: 84532`) |
| CRE Integration | Chainlink Runtime Environment (triggers + workflows) |
| Resolver API | Python, FastAPI, uvicorn |
| Chain Reads/Writes | web3.py |
| Config | python-dotenv |

---

## Project Structure

```text
base-escrow/
├── contracts/
│   └── Escrow.vy                         # Vyper escrow contract
├── cre/
│   ├── triggers/
│   │   ├── dispute_opened.trigger.yaml  # CRE: fires on Disputed event
│   │   └── deadline_scan.trigger.yaml   # CRE: periodic scan trigger
│   └── workflows/
│       └── dispute_resolution.workflow.yaml  # CRE: resolver → tx submission
├── resolver/
│   ├── src/
│   │   ├── api.py                       # FastAPI /resolve endpoint
│   │   ├── chain_client.py              # web3.py contract reads/writes
│   │   ├── policy.py                    # resolution policy engine
│   │   ├── config.py                    # env config loader
│   │   ├── types.py                     # EscrowState, ResolutionDecision
│   │   └── evidence.py                  # evidence hash verification
│   ├── abi/
│   │   └── Escrow.json                  # contract ABI for resolver
│   ├── config/
│   │   └── .env.example                 # resolver env template
│   └── requirements.txt
├── scripts/
│   ├── deploy.py                        # deploy Escrow.vy to Base Sepolia
│   └── interact.py                      # CLI: deposit, dispute, release, status
├── out/
│   ├── Escrow.abi.json
│   └── Escrow.address.txt
├── switch-role.sh                       # switch active wallet role
└── HOW_TO_REPRODUCE.md
```

---

## State Machine

```text
AWAITING_DEPOSIT → FUNDED → RELEASED
                    → DISPUTED → REFUNDED
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

---

## Setup

### 1. Clone and install

```bash
git clone https://github.com/CryptoAI-Jedi/base-escrow.git
cd base-escrow
```

### 2. Contract scripts (deploy + interact)

```bash
pip install web3 vyper python-dotenv
```

Create role env files (`env.deploy`, `env.buyer`, `env.seller`, `env.arbiter`) — see [HOW_TO_REPRODUCE.md](./HOW_TO_REPRODUCE.md).

### 3. Resolver service

```bash
cd resolver
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp config/.env.example config/.env
# Edit config/.env with your contract address, signer key, and API token
```

---

## Running the Resolver

**Start the API server:**
```bash
cd resolver
source .venv/bin/activate
uvicorn src.api:app --host 0.0.0.0 --port 8080 --reload
```

**Health check:**
```bash
curl http://127.0.0.1:8080/health
# {"status":"ok"}
```

**Query resolution for a disputed escrow:**
```bash
curl -X POST http://127.0.0.1:8080/resolve \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <RESOLVER_API_TOKEN>" \
  -d '{"mode": "single", "escrow_id": "<ESCROW_CONTRACT_ADDRESS>"}'
```

**Run the batch resolver (submits on-chain tx):**
```bash
cd resolver
source .venv/bin/activate
python -m src.main
```

---

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

# 4. CRE resolver detects DISPUTED state and refunds autonomously
cd resolver && python -m src.main
# [CHAIN] refund tx=0x... status=1 reason=DISPUTED_ARBITER_REFUND

# 5. Verify final state
cd .. && python scripts/interact.py status
# status: REFUNDED | amount: 0 ETH
```

---

## Troubleshooting

- `replacement transaction underpriced` — wait 15–30 seconds and retry
- Role actions revert — check current state: `python scripts/interact.py status`
- Activate venv before running Python: `source resolver/.venv/bin/activate`

---

## Security Notes

- Never commit private keys or `.env` files — all `env.*` and `config/.env` are gitignored
- Arbiter address = resolver signer address; keep the signer key secure
- Testnet only — not audited for mainnet use

---

## License

MIT
