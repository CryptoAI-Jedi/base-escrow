# Base Escrow — CRE-Powered Dispute Resolution on Base

A non-custodial escrow protocol on Base Sepolia where **Chainlink CRE autonomously monitors disputes and triggers on-chain resolution** without manual arbiter intervention.

> **Convergence: A Chainlink Hackathon submission**
> Tracks entered: **CRE & AI** | **DeFi & Tokenization** | **Top 10 Projects**

---

## Project Highlights

- Role-gated escrow state machine in **Vyper** deployed on Base Sepolia
- **Chainlink CRE** event trigger watches for `Disputed` events and dispatches a resolution workflow
- **FastAPI resolver service** reads live contract state via web3.py, evaluates a deterministic policy, and returns a resolution decision (`REFUND` or `RELEASE`)
- **Claude Haiku AI assessment** classifies each dispute, confirms policy alignment, and generates a rationale — advisory only, never overrides the deterministic outcome
- Resolver submits the onchain transaction autonomously — no human arbiter action required
- Full end-to-end demo: deposit → dispute → CRE resolver + AI assessment → confirmed refund tx onchain

---

## Why this fits CRE & AI

Base Escrow fits the **CRE & AI** category because it demonstrates an **autonomous decision-and-execution loop** for a real Web3 workflow: a dispute event onchain triggers a CRE workflow, the workflow calls an external resolver service, the resolver evaluates the escrow state with a deterministic policy engine, and CRE executes the corresponding onchain action.

In the current MVP, AI is already integrated as an **advisory assessment layer**. It can classify the dispute, confirm policy alignment, and generate a concise rationale for logging and operator visibility. However, the deterministic policy engine remains authoritative, and the AI layer never overrides the action or execution gating. This makes the project a practical example of **AI-assisted, verifiable automation** rather than an unverifiable black-box demo.

## Why this fits DeFi & Tokenization

Base Escrow also fits the **DeFi & Tokenization** category because it turns a traditionally manual commerce primitive into a **programmable onchain financial workflow**. The escrow contract holds value in a non-custodial way, enforces explicit state transitions, and supports transparent release or refund outcomes directly on Base Sepolia.

Even in this MVP form, the project demonstrates several DeFi-relevant properties:

- **non-custodial value handling** through smart-contract escrow,
- **programmable settlement logic** for buyer/seller transactions,
- **transparent onchain finality** for release and refund outcomes,
- **composable infrastructure** that can later support marketplace routing, milestone payments, and tokenized service agreements,
- and a foundation for **machine-to-machine commercial transactions** where autonomous agents can initiate, monitor, and pay for resolution services.

While the current demo uses native-value escrow on testnet rather than tokenized real-world assets, the architecture is directly extensible to **stablecoin settlement, tokenized invoices, milestone receipts, and other tokenized commerce flows**.

## Autonomous Architecture

> Note: The official **Autonomous Agents** prize track at Convergence is restricted to projects built on Moltbook. This project is not entered in that track.

That said, base-escrow is architecturally an autonomous agent system. When the Escrow contract emits a `Disputed` event, the CRE trigger fires without any human action, the resolver evaluates live onchain state, Claude Haiku assesses the decision, and CRE submits the settlement transaction autonomously. The full agent loop — **observe → decide (+ AI advisory) → write onchain** — is demonstrated with confirmed onchain evidence.

---

## Chainlink CRE Integration

All CRE-related files are in the [`cre/`](./cre/) directory.

### Trigger — [`cre/triggers/dispute_opened.trigger.yaml`](./cre/triggers/dispute_opened.trigger.yaml)

Watches the deployed Escrow contract on Base Sepolia for the `Disputed` event. When a dispute is opened, dispatches the resolution workflow with the contract address as the escrow identifier.

### Workflow — [`cre/workflows/dispute_resolution.workflow.yaml`](./cre/workflows/dispute_resolution.workflow.yaml)

1. **`resolve` step** — HTTP POST to the resolver API (`/resolve`) with the escrow ID
2. **`guard_action` step** — conditional gate: only proceeds if `should_submit_tx == true`
3. **`submit_tx` step** — CRE submits the `RELEASE` or `REFUND` transaction onchain
4. **`trace` step** — logs the resolution result with tx hash and reason code

### Resolver Service — [`resolver/`](./resolver/)

FastAPI service that acts as the "brain" for CRE:
- `src/api.py` — `/resolve` endpoint (bearer auth, returns resolution decision)
- `src/chain_client.py` — reads escrow state from Base via web3.py; submits `release()` / `refund()` txs
- `src/policy.py` — deterministic policy: `DISPUTED → REFUND`, `FUNDED → NONE`
- `src/config.py` — env-based config with absolute path resolution (works regardless of CWD)

### MVP Limitation — Dispute Abuse / Resolver Simplification

In the current MVP, **opening a dispute does not let the buyer unilaterally withdraw funds at the contract level** — only the arbiter / resolver signer can execute `refund()`. However, the present demo resolver intentionally uses a simplified deterministic rule of **`DISPUTED → REFUND`** to demonstrate the end-to-end CRE automation loop. That means this version is suitable for showing autonomous dispute handling, but **it is not yet a production-grade marketplace dispute policy**. A production version would replace this simplified rule with evidence-aware adjudication, review windows, conditional release / refund logic, and anti-abuse controls such as dispute bonds, delivery proofs, or timeout-based settlement.

### Live Demo Evidence

Contract: `0x9ff0c475EDB2Cbba77eCc0B6dFDd479f398b8360` (Base Sepolia)

**Demo Video:** [Loom — Base Escrow CRE Dispute Resolution](https://www.loom.com/share/64ff611cd8d74a45b04bdd49f22fbf1f)

| Step | Actor | Tx Hash | Result |
|---|---|---|---|
| Deploy | Arbiter | *(session)* | `AWAITING_DEPOSIT` |
| Deposit | Buyer | *(session)* | `FUNDED` |
| Dispute | Seller | *(session)* | `DISPUTED` |
| CRE Resolver Refund | Resolver | *(see README_test_evidence.md)* | `REFUNDED` |

**Resolver API response (with AI assessment):**
```json
{
  "escrow_id": "0x9ff0c475EDB2Cbba77eCc0B6dFDd479f398b8360",
  "action": "REFUND",
  "reason_code": "DISPUTED_ARBITER_REFUND",
  "should_submit_tx": true,
  "ai_assessment": {
    "classification": "disputed_arbiter_refund",
    "policy_alignment": "confirmed",
    "rationale": "The escrow contract is in DISPUTED status with a deterministic policy decision to REFUND based on arbiter intervention. This outcome is appropriate as the dispute has been formally adjudicated through the arbiter mechanism, and refunding the buyer represents a legitimate resolution pathway when an arbiter determines the seller has failed to fulfill contractual obligations."
  }
}
```

Full evidence: [README_test_evidence.md](./README_test_evidence.md)

---

## Architecture

```
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
    │ evaluates deterministic policy (always authoritative)
    │   └─▶ Claude Haiku: classify dispute + confirm alignment [advisory]
    │ returns { action, should_submit_tx, ai_assessment }
    ▼
CRE submits refund() onchain
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
| AI Assessment | Claude Haiku (`claude-haiku-4-5-20251001`), Anthropic SDK |
| Config | python-dotenv |

---

## Project Structure

```
base-escrow/
├── contracts/
│   └── Escrow.vy                    # Vyper escrow contract
├── cre/
│   ├── triggers/
│   │   ├── dispute_opened.trigger.yaml    # CRE: fires on Disputed event
│   │   └── deadline_scan.trigger.yaml     # CRE: periodic scan trigger
│   └── workflows/
│       └── dispute_resolution.workflow.yaml  # CRE: resolver → tx submission
├── resolver/
│   ├── src/
│   │   ├── api.py                    # FastAPI /resolve endpoint
│   │   ├── chain_client.py           # web3.py contract reads/writes
│   │   ├── policy.py                 # deterministic resolution policy engine
│   │   ├── ai_assessor.py            # Claude Haiku advisory dispute assessment
│   │   ├── main.py                   # batch resolver loop (reads API, submits tx)
│   │   ├── config.py                 # env config loader
│   │   ├── types.py                  # EscrowState, ResolutionDecision
│   │   └── evidence.py               # evidence hash verification
│   ├── abi/
│   │   └── Escrow.json                    # contract ABI for resolver
│   ├── config/
│   │   └── .env.example                   # resolver env template
│   └── requirements.txt
├── scripts/
│   ├── deploy.py                    # deploy Escrow.vy to Base Sepolia
│   └── interact.py                    # CLI: deposit, dispute, release, status
├── out/
│   ├── Escrow.abi.json
│   └── Escrow.address.txt
├── switch-role.sh                    # switch active wallet role
└── HOW_TO_REPRODUCE.md
```

---

## State Machine

```
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

Create role env files (`env.buyer`, `env.seller`, `env.arbiter`) — see [HOW_TO_REPRODUCE.md](./HOW_TO_REPRODUCE.md).

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

**Run the batch resolver (submits onchain tx):**
```bash
cd resolver
source .venv/bin/activate
python -m src.main
```

---

## End-to-End Demo Flow

```bash
# 1. Deploy (arbiter key signs the deployment)
./switch-role.sh arbiter && python scripts/deploy.py

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
- Current resolver policy is intentionally simplified for demo purposes; production dispute resolution should include stronger anti-abuse controls

---

## License

MIT
