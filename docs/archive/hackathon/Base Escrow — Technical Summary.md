> **Repository:** [`CryptoAI-Jedi/base-escrow`](https://github.com/CryptoAI-Jedi/base-escrow)
> **Network:** Base Sepolia (`chainId: 84532`)
> **Status:** Working MVP + CRE resolver scaffold (hackathon stage)
> **Last updated:** 2026-03-07

This document is the engineering hand-off reference for the Base Escrow project. It is intended to let any engineer pick up the project, understand every moving part, run it locally, and continue building toward a production-grade, Chainlink-CRE-driven escrow protocol.

---

## 1. Executive Summary

**Base Escrow** is a commerce-focused escrow protocol on **Base** designed for marketplace and milestone payments. It combines:

1. **An on-chain escrow smart contract** (`Escrow.vy`, written in Vyper) that holds buyer funds and enforces a strict state machine with three roles — **buyer, seller, arbiter**.
2. **An off-chain resolver service** (Python / FastAPI) that evaluates dispute policies, validates evidence hash commitments, and decides whether to RELEASE or REFUND funds with reason-coded traces.
3. **A Chainlink CRE (Compute Runtime Environment) workflow layer** (declarative YAML) that triggers the resolver on schedule (deadline scans) and on-chain events (dispute opened), then submits the resulting on-chain transaction.

The core value proposition: **transparent, deterministic, automated dispute resolution.** Instead of a human arbiter manually deciding every dispute, the system uses time-based deadlines and verifiable evidence-hash matching to drive deterministic on-chain outcomes — while still preserving an arbiter role as a fallback.

### Key Features
- Explicit escrow state machine (`AWAITING_DEPOSIT → FUNDED → RELEASED / REFUNDED / DISPUTED`)
- Role-based access control (buyer / seller / arbiter)
- Non-reentrancy guard on all fund-moving functions
- Off-chain policy engine with reason codes (`AUTO_RELEASE_TIMEOUT`, `SELLER_INACTIVE_VALID_EVIDENCE`, etc.)
- Evidence hash verification via canonical-JSON SHA-256
- Token-authenticated resolver API (`Bearer` token)
- Chainlink CRE triggers + workflow for automated execution
- Reproducible CLI test flow on live Base Sepolia (verified tx hashes)

---

## 2. Architecture Overview

The system is split across three layers that interact in a clear pipeline:

```
                ┌─────────────────────────────────────────────────────────┐
                │                    CHAINLINK CRE LAYER                    │
                │                                                           │
   on schedule  │   deadline_scan.trigger ──┐                              │
   (every 60s)  │                            ├──▶  dispute_resolution      │
   on event     │   dispute_opened.trigger ──┘     .workflow.yaml          │
 (DisputeOpened)│                                       │                  │
                └───────────────────────────────────────┼──────────────────┘
                                                         │ HTTP POST /resolve
                                                         │ (Bearer token)
                ┌────────────────────────────────────────▼──────────────────┐
                │                  RESOLVER SERVICE (FastAPI)                 │
                │                                                            │
                │   api.py ──▶ chain_client.get_open_escrows()               │
                │      │           │                                         │
                │      │           ▼                                         │
                │      └──▶ policy.evaluate_policy(escrow)                    │
                │                  │      ▲                                   │
                │                  │      │ evidence.evidence_hash_matches()  │
                │                  ▼                                         │
                │       ResolutionDecision(action, reason_code,              │
                │                           should_submit_tx)                │
                └────────────────────────────────────────┬──────────────────┘
                                                          │ submit_release / submit_refund
                                                          │ (or CRE blockchain_transaction step)
                ┌──────────────────────────────────────────▼────────────────┐
                │              ON-CHAIN: Escrow.vy (Base Sepolia)             │
                │                                                            │
                │   deposit() → release() / refund() / mark_dispute()        │
                │   State machine + reentrancy guard + role gating           │
                └────────────────────────────────────────────────────────────┘
```

### Component interaction (dispute flow)
1. A buyer/seller calls `mark_dispute()` on-chain → emits a `Disputed` event.
2. The CRE **`dispute_opened` trigger** fires (or the **`deadline_scan` trigger** fires on its 60s schedule).
3. CRE dispatches the **`dispute_resolution` workflow**, which makes an authenticated `POST /resolve` call to the resolver.
4. The resolver reads open escrows, runs `evaluate_policy`, and returns an action (`RELEASE` / `REFUND` / `HOLD` / `NONE`) with a reason code and a `should_submit_tx` flag.
5. If `should_submit_tx == true`, the CRE workflow's `submit_tx` step (a `blockchain_transaction`) executes the corresponding on-chain method, and the `trace` step logs the full reason-coded outcome.

> **Note on the two execution paths:** The resolver itself contains `submit_release` / `submit_refund` helpers in `chain_client.py` (currently mocked), AND the CRE workflow has its own `blockchain_transaction` step. The intended production design is for CRE to own tx submission (so the resolver stays a pure decision service), but the resolver's mock submit functions are useful for standalone/local testing. This duplication should be resolved as the project matures (see §10).

---

## 3. Tech Stack

| Layer | Technology | Version / Notes |
|---|---|---|
| Smart contract language | **Vyper** | `0.4.3` |
| Target chain | **Base Sepolia** (EVM L2) | `chainId: 84532`, RPC `https://sepolia.base.org` |
| Contract tooling | `vyper` (compiler), `web3.py`, `eth-account` | Used in `scripts/deploy.py` & `interact.py` |
| Resolver service | **Python 3.11**, **FastAPI**, **Uvicorn** | ASGI server |
| Resolver deps | `pyyaml`, `requests`, `python-dotenv`, `fastapi`, `uvicorn` | See `resolver/requirements.txt` |
| Evidence hashing | `hashlib` (SHA-256), canonical JSON | stdlib |
| Orchestration | **Chainlink CRE** | Declarative YAML triggers + workflow |
| Config management | `.env` files via `python-dotenv` | absolute-path loading (see `config.py`) |
| Monitoring (ops) | **Prometheus** + **Grafana** + **Node Exporter** | `prometheus.yml`, Node Exporter Full dashboard |

---

## 4. Smart Contract Details (`Escrow.vy`)

A **single-escrow-per-instance** contract: each deployment manages exactly one buyer/seller/arbiter triple and one fund amount.

### State Machine
| Value | Constant | Meaning |
|---|---|---|
| `0` | `STATUS_AWAITING_DEPOSIT` | Deployed, no funds yet |
| `1` | `STATUS_FUNDED` | Buyer has deposited |
| `2` | `STATUS_RELEASED` | Funds sent to seller (terminal) |
| `3` | `STATUS_REFUNDED` | Funds returned to buyer (terminal) |
| `4` | `STATUS_DISPUTED` | Dispute / refund-intent marker |

Valid transitions:
```
AWAITING_DEPOSIT ──deposit()──▶ FUNDED
FUNDED ──release()──▶ RELEASED          (buyer or arbiter)
FUNDED ──mark_dispute()──▶ DISPUTED     (buyer or seller)
FUNDED ──approve_refund()──▶ DISPUTED   (arbiter)
DISPUTED ──release()──▶ RELEASED        (buyer or arbiter)
DISPUTED ──refund()──▶ REFUNDED         (arbiter only)
```

### State Variables
| Variable | Type | Visibility | Purpose |
|---|---|---|---|
| `status` | `uint256` | public | Current state machine value |
| `buyer` | `address` | public | Buyer address |
| `seller` | `address` | public | Seller address |
| `arbiter` | `address` | public | Arbiter / mediator address |
| `amount` | `uint256` | public | Escrowed ETH amount (wei) |
| `lock` | `uint256` | private | Simple non-reentrant lock (0 = free, 1 = entered) |

### Key Functions
| Function | Caller(s) | Pre-state | Post-state | Notes |
|---|---|---|---|---|
| `__init__(_buyer, _seller, _arbiter)` | deployer | — | `AWAITING_DEPOSIT` | Validates non-zero addrs; `buyer != seller` |
| `deposit()` `@payable` | buyer | `AWAITING_DEPOSIT` | `FUNDED` | `msg.value > 0`; single-shot funding; reentrancy-guarded |
| `mark_dispute()` | buyer **or** seller | `FUNDED` | `DISPUTED` | Either party can flag a dispute |
| `approve_refund()` | arbiter | `FUNDED` or `DISPUTED` | `DISPUTED` | MVP: approval signaled by `DISPUTED` status |
| `release()` | buyer **or** arbiter | `FUNDED` or `DISPUTED` | `RELEASED` | Sends `amount` to seller; reentrancy-guarded |
| `refund()` | arbiter only | `DISPUTED` | `REFUNDED` | Sends `amount` to buyer; reentrancy-guarded |
| `set_buyer(_buyer)` | arbiter | `AWAITING_DEPOSIT` | — | Operational recovery before funding |
| `set_seller(_seller)` | arbiter | `AWAITING_DEPOSIT` | — | Operational recovery before funding |
| `set_arbiter(_arbiter)` | arbiter | any | — | Transfer arbiter role |

### Events
| Event | Indexed fields | Emitted by |
|---|---|---|
| `Deposited` | `buyer`, `amount` | `deposit()` |
| `Released` | `by`, `to`, `amount` | `release()` |
| `RefundApproved` | `by` | `approve_refund()` |
| `Refunded` | `by`, `to`, `amount` | `refund()` |
| `Disputed` | `by` | `mark_dispute()` |
| `ArbiterUpdated` | `old_arbiter`, `new_arbiter` | `set_arbiter()` |
| `SellerUpdated` | `old_seller`, `new_seller` | `set_seller()` |
| `BuyerUpdated` | `old_buyer`, `new_buyer` | `set_buyer()` |

### Access Control & Security Mechanisms
- **Role gating** via `assert msg.sender == self.<role>` checks on every sensitive function.
- **Non-reentrancy lock** (`_nonreentrant_enter` / `_nonreentrant_exit`) wrapping all ETH-moving functions (`deposit`, `release`, `refund`).
- **Checks-Effects-Interactions**: state (`amount = 0`, `status = ...`) is updated *before* `send()` in `release`/`refund`.
- **Funds via `send()`**: forwards limited gas (caution — see §10 for a recommended `raw_call`/pull-payment upgrade).

> ⚠️ **Naming discrepancy to be aware of:** The on-chain event for disputes is `Disputed`, but the CRE `dispute_opened.trigger.yaml` listens for an event named **`DisputeOpened`** with field `escrowId`. The contract currently emits neither that event name nor an `escrowId`/`escrow_id` field. **This must be reconciled** for the event trigger to fire (see §10).

---

## 5. Resolver Service Details (`resolver/`)

A FastAPI service that acts as the **decision brain** for dispute resolution. It is intentionally a pure(ish) policy service: given escrow state, it returns *what should happen* and *why*.

### Module map
| File | Responsibility |
|---|---|
| `src/config.py` | Loads `.env` from an **absolute path** (works from any CWD); exports typed config constants + `validate_chain_config()` |
| `src/__init__.py` | Imports `config` first so env vars are available to all submodules |
| `src/types.py` | `EscrowState` and `ResolutionDecision` dataclasses |
| `src/evidence.py` | Canonical-JSON SHA-256 hashing + evidence fetch + hash match |
| `src/policy.py` | `evaluate_policy()` — the deterministic rule engine |
| `src/chain_client.py` | On-chain reads/writes (currently mocked TODOs) |
| `src/api.py` | FastAPI app: `POST /resolve`, `GET /health` |
| `src/main.py` | Standalone batch loop (`run_once()`) for non-API execution |

### Data structures (`types.py`)
```python
@dataclass
class EscrowState:
    escrow_id: str
    status: str                      # FUNDED, DISPUTED, RELEASED, REFUNDED
    buyer: str
    seller: str
    evidence_uri: Optional[str]
    evidence_hash: Optional[str]
    release_deadline_ts: int
    seller_response_deadline_ts: int
    disputed_at_ts: Optional[int]

@dataclass
class ResolutionDecision:
    action: str          # RELEASE, REFUND, HOLD, NONE
    reason_code: str
    should_submit_tx: bool
```

### Policy engine (`policy.py`)
Deterministic rules, evaluated against the current UNIX time:

| Rule | Condition | Decision | Reason Code | Submit tx? |
|---|---|---|---|---|
| Auto-release timeout | `status == FUNDED` and `now > release_deadline_ts` | `RELEASE` | `AUTO_RELEASE_TIMEOUT` | ✅ |
| Missing evidence | `status == DISPUTED` and (no `evidence_uri` or no `evidence_hash`) | `HOLD` | `MISSING_EVIDENCE` | ❌ |
| Evidence mismatch | `status == DISPUTED` and hash doesn't match | `HOLD` | `EVIDENCE_HASH_MISMATCH` | ❌ |
| Seller inactive + valid evidence | `status == DISPUTED`, valid evidence, `now > seller_response_deadline_ts` | `REFUND` | `SELLER_INACTIVE_VALID_EVIDENCE` | ✅ |
| Default | none of the above | `NONE` | `NO_ACTION` | ❌ |

### Evidence verification (`evidence.py`)
- `canonical_json_hash(payload)` → `json.dumps(payload, separators=(",",":"), sort_keys=True)` then SHA-256 hex digest. Canonicalization guarantees a deterministic hash regardless of key ordering / whitespace.
- `fetch_evidence_json(uri)` → fetches over HTTP(S) (10s timeout) or reads a local file.
- `evidence_hash_matches(uri, onchain_hash)` → compares the recomputed hash against the on-chain committed hash.

### API endpoints (`api.py`)
| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| `POST` | `/resolve` | `Authorization: Bearer <RESOLVER_API_TOKEN>` | `{"mode": "single"\|"scan", "escrow_id": "<id>"?}` | resolution decision JSON |
| `GET` | `/health` | none | — | `{"status": "ok"}` |

**Example request:**
```bash
curl -X POST http://127.0.0.1:8080/resolve \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dev-token-12345" \
  -d '{"mode": "single", "escrow_id": "test-123"}'
```

**Example response (no escrows yet, since chain reads are mocked):**
```json
{
  "escrow_id": "test-123",
  "action": "NONE",
  "reason_code": "NO_ESCROW_FOUND",
  "should_submit_tx": false
}
```

### Authentication
- A static bearer token (`RESOLVER_API_TOKEN`) is compared against the `Authorization` header.
- Missing server token → `500`; mismatched token → `401`.
- The same token is injected by the CRE workflow as `Authorization: Bearer ${RESOLVER_API_TOKEN}`.

### Chain interaction (`chain_client.py`) — current state
All three functions are **mocked placeholders**:
- `get_open_escrows()` → returns `[]` (so loops/endpoints run safely). Calls `validate_chain_config()` and logs a warning if config is incomplete.
- `submit_release(escrow_id, reason_code)` → returns `0xmock_release_tx_...`
- `submit_refund(escrow_id, reason_code)` → returns `0xmock_refund_tx_...`

These are the **primary integration points** for real `web3.py` calls (see §10).

### Configuration loading (`config.py`) — important design detail
`config.py` resolves the config directory via `Path(__file__).resolve()` and loads `resolver/config/.env` (falling back to `.env.example`) using an **absolute path**. This fixes a class of bugs where the service only worked when launched from the project root. Always run the service so that `src` is importable (see §9).

---

## 6. Chainlink CRE Layer (`cre/`)

Declarative YAML that wires on-chain/off-chain automation.

### `cre/triggers/deadline_scan.trigger.yaml`
- **Type:** schedule (`every: 60s`)
- **Dispatches:** `dispute-resolution-workflow` with `mode: "scan"`
- **Purpose:** periodically sweep for escrows that have crossed a deadline (auto-release / seller-inactive refund).

### `cre/triggers/dispute_opened.trigger.yaml`
- **Type:** event listener on the escrow contract
- **Listens for:** event `DisputeOpened` with field `escrowId`
- **Dispatches:** `dispute-resolution-workflow` with `mode: "single", escrow_id: <id>`
- ⚠️ See §4 discrepancy — the contract emits `Disputed` (no `escrowId`), not `DisputeOpened`.

### `cre/workflows/dispute_resolution.workflow.yaml`
Steps:
1. **`resolve`** — `http_request` `POST ${RESOLVER_BASE_URL}/resolve` with bearer auth and body `{mode, escrow_id}`.
2. **`guard_action`** — `conditional`, proceeds only when `steps.resolve.response.should_submit_tx == true`.
3. **`submit_tx`** — `blockchain_transaction` on Base Sepolia, calling the contract method named by `steps.resolve.response.action` (`RELEASE`/`REFUND`) with `escrow_id` + `reason_code` args, signed by `RESOLVER_SIGNER_PRIVATE_KEY`.
4. **`trace`** — `log` step emitting a structured, reason-coded audit record (`escrow_id`, `action`, `reason_code`, `tx_hash`, `mode`).

> ⚠️ **Method-name mismatch:** the workflow passes `action` (e.g. `RELEASE`/`REFUND`, uppercase) directly as the contract method. The actual contract methods are lowercase `release()` / `refund()` and take **no arguments** (single-escrow-per-instance). A mapping/adapter layer is needed (see §10).

---

## 7. Project Structure

```
base-escrow/
├── contracts/
│   └── Escrow.vy                      # Vyper escrow smart contract (0.4.3)
├── scripts/
│   ├── deploy.py                      # Compile + deploy Escrow.vy to Base Sepolia
│   └── interact.py                    # CLI: status/deposit/release/dispute/refund
├── out/
│   ├── Escrow.abi.json                # Compiled ABI (consumed by interact.py)
│   ├── Escrow.bytecode.txt            # Compiled bytecode
│   └── Escrow.address.txt             # Latest deployed address
├── resolver/
│   ├── config/
│   │   ├── .env                       # Local secrets/config (gitignored)
│   │   └── .env.example               # Template
│   ├── requirements.txt               # Resolver Python deps
│   └── src/
│       ├── __init__.py                # Loads config first
│       ├── config.py                  # Absolute-path .env loader + validation
│       ├── types.py                   # EscrowState / ResolutionDecision
│       ├── evidence.py                # Canonical-JSON SHA-256 evidence matching
│       ├── policy.py                  # Deterministic rule engine
│       ├── chain_client.py            # Chain reads/writes (MOCKED — TODO)
│       ├── api.py                     # FastAPI /resolve + /health
│       └── main.py                    # Standalone batch loop (run_once)
├── cre/
│   ├── triggers/
│   │   ├── deadline_scan.trigger.yaml # 60s schedule → scan mode
│   │   └── dispute_opened.trigger.yaml# event → single mode
│   └── workflows/
│       └── dispute_resolution.workflow.yaml  # resolve → guard → submit_tx → trace
├── switch-role.sh                     # Copies env.<role> → .env (buyer/seller/arbiter)
├── HOW_TO_REPRODUCE.md                # < 5 min reproduction guide
├── README.md                          # Project README
├── README_test_evidence.md            # Verified on-chain test evidence + tx hashes
├── .env.example
└── .gitignore
```

---

## 8. Configuration

### Resolver env (`resolver/config/.env`)
| Variable | Required | Default | Purpose |
|---|---|---|---|
| `NETWORK_NAME` | no | `base-sepolia` | Network label |
| `CHAIN_ID` | no | `84532` | Base Sepolia chain id |
| `RPC_URL` | **for chain ops** | `https://sepolia.base.org` | JSON-RPC endpoint |
| `ESCROW_CONTRACT_ADDRESS` | **for chain ops** | — | Deployed escrow address |
| `RESOLVER_BASE_URL` | no | `http://127.0.0.1:8080` | Where CRE calls the resolver |
| `RESOLVER_API_TOKEN` | **yes (API)** | — | Bearer token for `/resolve` |
| `RESOLVER_SIGNER_PRIVATE_KEY` | **for tx submit** | — | Signer key for on-chain tx |
| `RESOLVER_SIGNER_ADDRESS` | for tx submit | — | Signer address |
| `POLL_INTERVAL_SECONDS` | no | `30` | Batch loop poll interval |
| `LOG_LEVEL` | no | `INFO` | Logging level |

`validate_chain_config()` enforces presence of `RPC_URL`, `ESCROW_CONTRACT_ADDRESS`, and `RESOLVER_SIGNER_PRIVATE_KEY` before any real chain operation.

### Contract scripts env (root `.env`, swapped by `switch-role.sh`)
Deploy (`env.deploy`): `RPC_URL`, `CHAIN_ID`, `PRIVATE_KEY` (deployer/arbiter), `BUYER_ADDRESS`, `SELLER_ADDRESS`, `ARBITER_ADDRESS`.
Per-role (`env.buyer` / `env.seller` / `env.arbiter`): `RPC_URL`, `CHAIN_ID`, `PRIVATE_KEY`.

`switch-role.sh <role>` copies `env.<role>` → `.env` (chmod 600) and prints a masked summary (never prints the private key).

> 🔐 **Secrets policy:** `.env`, `env.*`, and `resolver/config/.env` are gitignored. Never commit private keys. This is a testnet/educational project — **not audited for mainnet**.

### Monitoring (`prometheus.yml`)
Operational monitoring config (separate from the app). Scrapes: Prometheus self (`:9090`), Node Exporter system metrics (`:9100`), and placeholder jobs for Bitcoin/Monero/ASIC fleet. A Grafana "Node Exporter Full" dashboard visualizes CPU/RAM/disk/network. **TODO noted in file:** add alert rules (`alerts/node_alerts.yml`) for high CPU / low peers / block lag.

---

## 9. Setup, Run & Test

### Prerequisites
- Python 3.11+
- A funded Base Sepolia wallet (test ETH) for on-chain flows

### A) Smart contract — deploy & interact
```bash
git clone https://github.com/CryptoAI-Jedi/base-escrow.git
cd base-escrow
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt        # web3, eth-account, vyper, python-dotenv

# Configure deploy env (buyer/seller/arbiter addresses + deployer key)
cp env.deploy .env
python scripts/deploy.py
cat out/Escrow.address.txt
```

Full dispute/refund proof (role switching):
```bash
./switch-role.sh buyer
python scripts/interact.py deposit --eth 0.0001

./switch-role.sh seller
python scripts/interact.py mark_dispute

./switch-role.sh arbiter
python scripts/interact.py approve_refund
python scripts/interact.py refund

python scripts/interact.py status   # expect: status REFUNDED, amount 0
```

### B) Resolver service
```bash
cd resolver
pip install -r requirements.txt
cp config/.env.example config/.env    # then edit values (set RESOLVER_API_TOKEN etc.)

# Run the API (must run with src importable on PYTHONPATH)
PYTHONPATH=. uvicorn src.api:app --host 0.0.0.0 --port 8080
```

Verify:
```bash
curl http://localhost:8080/health
# {"status":"ok"}

curl -X POST http://localhost:8080/resolve \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dev-token-12345" \
  -d '{"mode":"single","escrow_id":"test-123"}'
# {"escrow_id":"test-123","action":"NONE","reason_code":"NO_ESCROW_FOUND","should_submit_tx":false}
```

Standalone batch loop (no HTTP):
```bash
cd resolver && PYTHONPATH=. python -m src.main
```

> ℹ️ Because `chain_client.get_open_escrows()` is mocked to return `[]`, the resolver currently always responds `NO_ESCROW_FOUND` / `NONE`. This is expected until real chain reads are wired in (§10).

### Verified test evidence (Base Sepolia)
From `README_test_evidence.md`:
- **Deployed contract:** `0x43F5cC8AF9c6dAD78Ebfd8d1700db40d52C82b70`
- Buyer `0x45FE…d2B4`, Seller `0x6A18…3790`, Arbiter `0xd518…255c`

| Step | Role | Tx Hash | Receipt | State |
|---|---|---|---|---|
| Deposit | Buyer | `0x7e9adf…986f8` | `1` | FUNDED |
| Approve Refund | Arbiter | `0x7f18b9…f0112` | `1` | DISPUTED |
| Refund | Arbiter | `0x2f4ef6…41d2b` | `1` | REFUNDED |

---

## 10. Current Status, Known Issues & Next Steps

### ✅ Implemented & working
- Vyper escrow contract with full state machine, role gating, reentrancy guard — **deployed and verified on Base Sepolia** with real tx evidence.
- Python deploy/interact CLI + role-switching workflow.
- Resolver FastAPI service: `/resolve` + `/health`, bearer auth (verified working), absolute-path config loading.
- Deterministic policy engine with reason codes.
- Canonical-JSON SHA-256 evidence verification.
- CRE trigger + workflow YAML scaffolding.
- Prometheus/Grafana ops monitoring config.

### ⚠️ Known issues / limitations
1. **Chain reads/writes are mocked.** `get_open_escrows()`, `submit_release()`, `submit_refund()` are placeholders — the resolver cannot yet see real escrow state or submit real tx.
2. **Event name mismatch.** Contract emits `Disputed` (no `escrowId`); CRE `dispute_opened` trigger expects `DisputeOpened(escrowId)`. The event trigger will not fire as-is.
3. **Workflow method/arg mismatch.** Workflow calls method `RELEASE`/`REFUND` with `(escrow_id, reason_code)` args; contract methods are lowercase `release()`/`refund()` with **no args** (single-escrow-per-instance). Needs an adapter or a contract redesign with multi-escrow `escrowId` keys + `resolveRelease/resolveRefund(escrowId, reasonCode)`.
4. **No on-chain evidence/deadline fields.** `EscrowState` expects `evidence_uri`, `evidence_hash`, `release_deadline_ts`, `seller_response_deadline_ts` — none exist in `Escrow.vy`. The contract has no concept of deadlines or evidence commitments yet.
5. **Single escrow per contract.** Doesn't scale to a marketplace; each escrow needs a fresh deployment.
6. **`send()` for transfers.** Limited-gas `send()` can fail for contract recipients; consider `raw_call` with explicit gas or a pull-payment pattern.
7. **Resolver vs CRE both submit tx.** Duplicate responsibility — decide one owner (recommended: CRE submits, resolver decides only).
8. **No automated tests / CI.** No unit tests for policy/evidence; no contract test suite.
9. **No alert rules** wired into Prometheus yet.

### 🔭 Recommended next steps (prioritized)
1. **Redesign contract for multi-escrow + automation hooks:** add `escrowId` mapping, `release_deadline_ts`, `seller_response_deadline_ts`, `evidence_hash` (bytes32) + `evidence_uri`, emit `DisputeOpened(escrowId)`, and add resolver-gated `resolveRelease(escrowId, reasonCode)` / `resolveRefund(escrowId, reasonCode)` callable only by the resolver signer.
2. **Implement real `chain_client`** with `web3.py`: read escrow state into `EscrowState`, and submit signed EIP-1559 tx for release/refund.
3. **Reconcile CRE workflow** action names → contract methods, and align trigger event name/fields.
4. **Add evidence storage** (IPFS/Arweave URI + on-chain hash commitment) and wire `evidence.py` to it.
5. **Add test coverage:** Vyper contract tests (e.g., with `titanoboa`/`pytest`), resolver unit tests for `policy.evaluate_policy` and `evidence.*`.
6. **Harden security:** replace `send()` with safer transfer, add events for resolver-driven resolutions, consider role/2-step ownership transfer, add rate limiting + token rotation on the resolver API.
7. **Add CI/CD** (lint, compile, test) and Prometheus alert rules.
8. **End-to-end CRE dry-run** on Base Sepolia: dispute → trigger → resolve → on-chain refund → trace log.

---

## 11. Glossary of Reason Codes

| Reason Code                      | Meaning                                                 | Resulting action  |
| -------------------------------- | ------------------------------------------------------- | ----------------- |
| `AUTO_RELEASE_TIMEOUT`           | Funded escrow passed release deadline                   | RELEASE to seller |
| `SELLER_INACTIVE_VALID_EVIDENCE` | Disputed, valid evidence, seller missed response window | REFUND to buyer   |
| `MISSING_EVIDENCE`               | Disputed but no evidence URI/hash                       | HOLD              |
| `EVIDENCE_HASH_MISMATCH`         | Evidence content doesn't match committed hash           | HOLD              |
| `NO_ACTION`                      | No rule triggered                                       | NONE              |
| `NO_ESCROW_FOUND`                | No matching escrow (API)                                | NONE              |