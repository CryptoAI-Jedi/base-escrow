# Base Escrow Market

An onchain marketplace on **Base** — listings, escrowed payments, and **automated dispute resolution** driven by a deterministic policy engine, Chainlink CRE, and an advisory AI assessor.

> Testnet project (Base Sepolia, `chainId: 84532`). **Not audited — do not use real funds.**
>
> The original single-escrow hackathon submission (Convergence: A Chainlink Hackathon) is preserved at the
> [`hackathon-submission`](../../tree/hackathon-submission) tag, with its evidence archived in
> [`docs/archive/hackathon/`](./docs/archive/hackathon/).

---

## How it works

1. **Sellers list items** — metadata (title, description, image) pinned to IPFS, price in ETH or USDC, category on-chain.
2. **Buyers purchase with escrow** — `buy(listingId)` atomically creates *and funds* an escrow; funds sit in the `EscrowMarket` contract, never with the seller.
3. **Happy path** — the buyer releases after delivery, or the escrow **auto-releases to the seller** after the release deadline.
4. **Disputes** — either party can dispute *before* the deadline, committing evidence to IPFS (the CID is the on-chain commitment). A FastAPI **resolver** verifies evidence by re-deriving its CID, applies a deterministic policy (auto-release timeout, missing/invalid evidence → hold, seller inactivity + valid evidence → refund), and returns an exact contract call. **Chainlink CRE** submits it on-chain. A Claude-based assessor adds an advisory classification — it can never move funds.
5. Funds can only ever flow to that escrow's **buyer or seller** (minus a capped protocol fee on release) — even a compromised resolver key cannot send them anywhere else.

```
Seller ──createListing──▶ ┌────────────────────┐ ◀──buy (ETH/USDC)── Buyer
                          │  EscrowMarket.sol  │
        DisputeOpened ◀── │   (Base Sepolia)   │ ◀── release / openDispute / submitEvidence
              │           └────────┬───────────┘
              ▼                    │ events                ▲
   ┌─────────────────┐     ┌──────▼──────┐                │ resolveRelease /
   │ Chainlink CRE   │     │   Ponder    │──GraphQL──▶ Web (Next.js)
   │ trigger+workflow│     │   indexer   │──discovery─▶ ┌───────────────┐
   └───────┬─────────┘     └─────────────┘              │   Resolver    │
           │  POST /resolve                             │ FastAPI + AI  │
           └───────────────────────────────────────────▶│ policy engine │
                       submits {method,args} on-chain ◀─┘ (decision-only)
```

## Monorepo layout

| Package | Stack | Purpose |
|---|---|---|
| [`contracts/`](./contracts) | Solidity 0.8.30, Foundry, OpenZeppelin v5 | `EscrowMarket.sol` — listings + multi-escrow + resolver gate + fees |
| [`indexer/`](./indexer) | Ponder, TypeScript | Indexes all market events; GraphQL for web + resolver discovery |
| [`resolver/`](./resolver) | Python 3.10+, FastAPI, web3.py | Deterministic dispute policy, evidence CID verification, advisory AI |
| [`web/`](./web) | Next.js (App Router), wagmi, RainbowKit, Tailwind | Browse/sell/buy/escrow UI; Pinata pinning route |
| [`cre/`](./cre) | Chainlink CRE YAML | `DisputeOpened` trigger + 60s deadline scan → resolve → submit tx |
| [`ops/`](./ops) | Prometheus | Scrape config + alert rules (resolver, indexer, protocol health) |
| [`docs/`](./docs) | — | [`ARCHITECTURE.md`](./docs/ARCHITECTURE.md), [`E2E.md`](./docs/E2E.md), [`PLAN.md`](./PLAN.md), hackathon archive |

## Quickstart (local stack)

Prereqs: Foundry, Node 20+, Python 3.10+.

```bash
# 1. Contracts — build & test (unit + fuzz + invariant suites)
cd contracts && forge test

# 2. Local chain + deployment
anvil --port 8546 --chain-id 84532 &
RESOLVER_ADDRESS=<resolver-signer> TREASURY_ADDRESS=<treasury> \
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8546 \
  --private-key <deployer-key> --broadcast
ESCROW_MARKET_ADDRESS=<deployed> forge script script/SeedListings.s.sol ... # optional demo data

# 3. Indexer
cd ../indexer && npm install
PONDER_RPC_URL_84532=http://127.0.0.1:8546 \
ESCROW_MARKET_ADDRESS=<deployed-address> npm run dev   # GraphQL on :42069

# 4. Resolver
cd ../resolver && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp config/.env.example config/.env   # set address, token, RPC
.venv/bin/uvicorn src.api:app --port 8080   # or: .venv/bin/python -m src.main

# 5. Web
cd ../web && npm install
cp .env.example .env.local           # set address, Ponder URL, Pinata JWT
npm run dev                          # http://localhost:3000
```

The full local flow (deploy → seed → buy → dispute → resolver decision → on-chain resolution → indexer/UI) is documented step-by-step in [`docs/E2E.md`](./docs/E2E.md).

## Dispute policy (deterministic, authoritative)

| Rule | Condition | Outcome | Reason code |
|---|---|---|---|
| Auto-release | `FUNDED` and past release deadline | `resolveRelease` | `AUTO_RELEASE_TIMEOUT` |
| Missing evidence | `DISPUTED`, no evidence CID | hold | `MISSING_EVIDENCE` |
| Invalid evidence | `DISPUTED`, CID unfetchable or content ≠ CID | hold | `EVIDENCE_HASH_MISMATCH` |
| Seller inactive | `DISPUTED`, valid evidence, response window passed | `resolveRefund` | `SELLER_INACTIVE_VALID_EVIDENCE` |

Evidence is uploaded as **CIDv1 / raw / sha2-256** (`bafkr…`) JSON, so the resolver can re-derive the hash from the fetched bytes — the IPFS CID *is* the integrity commitment. The AI assessment (Claude) is attached to responses for audit visibility and never gates execution.

## Security model (summary)

- Reentrancy-guarded, checks-effects-interactions; terminal states are absorbing.
- **Pull-payment fallback**: a reverting/blocklisted recipient can never block resolution — funds queue in `withdrawable` instead.
- Resolver authority is minimal: only `resolveRelease`/`resolveRefund`, only in valid states, only to that escrow's parties.
- Fee is snapshotted at purchase and hard-capped at 5% in the contract; refunds always return the full amount.
- `pause` stops new listings/purchases only — release, refund, dispute, and withdraw can never be paused.
- Full threat analysis in [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) and [PLAN.md §6](./PLAN.md).

## Testing & CI

- **Contracts**: 74 Foundry tests — full branch coverage, fuzz (fee math, deadline boundaries, access control), and invariants (exact per-token solvency, absorbing terminal states, exact treasury fees) with a randomized handler including an ETH-rejecting buyer.
- **Resolver**: 32 pytest tests (policy boundary table, CID verification vectors, API auth, AI failure isolation) + ruff.
- **Indexer/Web**: eslint + tsc + production build.
- GitHub Actions run all of the above per-path; a nightly job runs deep fuzz (10k runs); testnet deploys are a manual, environment-gated workflow.

## License

MIT
