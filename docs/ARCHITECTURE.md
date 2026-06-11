# Architecture

> Living engineering reference for Base Escrow Market. Supersedes the archived
> [Technical Summary](./archive/hackathon/Base%20Escrow%20—%20Technical%20Summary.md)
> (single-escrow MVP). Design rationale and the approved decision log live in
> [PLAN.md](../PLAN.md).

## Components

| Component | Path | Runtime | Role |
|---|---|---|---|
| EscrowMarket | `contracts/src/EscrowMarket.sol` | Base Sepolia | Listings, multi-escrow state machine, fees, resolver gate, pull-payment fallback |
| Indexer | `indexer/` | Node (Ponder) | Event → tables (`listing`, `escrow`, `evidenceSubmission`, `sellerStats`); GraphQL on `:42069` |
| Resolver | `resolver/` | Python (FastAPI) | **Decision-only** dispute policy + evidence verification + advisory AI; `POST /resolve`, `GET /health`, `GET /metrics` |
| CRE layer | `cre/` | Chainlink CRE | `DisputeOpened` event trigger + 60s deadline scan → call resolver → **submit the returned tx** |
| Web | `web/` | Next.js | Marketplace UI + server-side Pinata pinning (`/api/pin`) |
| Ops | `ops/` | Prometheus | Scrapes resolver/indexer; alert rules |

## Contract design

Single monolithic contract (`EscrowMarket`), escrows keyed by `escrowId`:

- **Listings**: `createListing(token, price, category, metadataCID)` / `updateListing` / `cancelListing`. `category` is `keccak256(slug)` (canonical slugs in `web/lib/categories.ts`). Price changes never affect open escrows (snapshot at purchase). Listings are reusable — multiple buyers can purchase the same listing.
- **Purchase = funding**: `buy(listingId)` (ETH, `msg.value == price`) or `buyERC20(listingId)` (whitelisted tokens, balance-delta-checked) atomically creates a `Funded` escrow. There is no unfunded escrow state.
- **State machine** (absorbing terminal states):

```
            buy()                       release() by buyer
              │                         resolveRelease() by resolver (past deadline)
              ▼                                   │
           FUNDED ────────────────────────────────┴──▶ RELEASED
              │ openDispute(evidenceCID)
              │ by buyer/seller, strictly BEFORE releaseDeadline
              ▼
          DISPUTED ──resolveRelease()──▶ RELEASED
              │  ▲                          ▲
              │  └── submitEvidence()       └── release() by buyer (concede)
              └────resolveRefund()─────▶ REFUNDED
```

- **Deadlines**: `releaseDeadline = funded_at + releaseWindow`; `sellerResponseDeadline = disputed_at + sellerResponseWindow`. `openDispute` requires `now < releaseDeadline` strictly, timeout `resolveRelease` requires `now > releaseDeadline` strictly — there is no timestamp where both are valid.
- **Fees**: `feeBps` (hard cap `MAX_FEE_BPS = 500`) snapshotted into `feeAmount` at purchase; charged only on release (treasury), never on refunds.
- **Payouts**: direct `call`/ERC-20 transfer under `nonReentrant` + CEI; on failure (reverting receiver, USDC blocklist, return-false token) the amount is credited to `withdrawable[recipient][token]` and `WithdrawalQueued` is emitted — resolution can never be blocked by a recipient.
- **Roles**: `Ownable2Step` owner (fees, treasury, resolver address, token whitelist, windows, pause), `resolver` (only `resolveRelease`/`resolveRefund`). `pause` gates `createListing`/`buy*` only.

### Events (consumed by indexer + CRE)

`ListingCreated/Updated/Cancelled`, `EscrowCreated`, `Released`, `Refunded`,
`DisputeOpened(escrowId indexed, by, evidenceCID, sellerResponseDeadline)`,
`EvidenceSubmitted`, `Resolved(escrowId, action, reasonCode)`,
`WithdrawalQueued`, plus admin events.

## Dispute resolution pipeline

1. `openDispute` emits `DisputeOpened(escrowId, …)` → CRE event trigger fires (the 60s `deadline_scan` trigger covers timeouts).
2. CRE workflow `POST /resolve` (bearer auth) with `{mode, escrow_id}`.
3. Resolver discovery: Ponder GraphQL (`status_in: [FUNDED, DISPUTED]`); on indexer failure it falls back to a bounded on-chain scan (`nextEscrowId`, last 500). **Every decision re-reads escrow state from the chain** — the indexer is only a hint.
4. Policy engine (deterministic, authoritative):

| Rule | Condition | Decision |
|---|---|---|
| Auto-release | FUNDED, `now > releaseDeadline` | `resolveRelease` / `AUTO_RELEASE_TIMEOUT` |
| Missing evidence | DISPUTED, empty CID | HOLD / `MISSING_EVIDENCE` |
| Invalid evidence | DISPUTED, CID undecodable, unfetchable, or content hash ≠ CID | HOLD / `EVIDENCE_HASH_MISMATCH` |
| Seller inactive | DISPUTED, valid evidence, `now > sellerResponseDeadline` | `resolveRefund` / `SELLER_INACTIVE_VALID_EVIDENCE` |
| Default | — | NONE / HOLD |

5. Response carries an exact call descriptor — `{"method": "resolveRefund", "args": {"escrowId": …, "reasonCode": "0x…"}}` — which the CRE `submit_tx` step executes **verbatim**. CRE owns production submission; the resolver's own submitter (`src/main.py`) is a dev harness gated behind `RESOLVER_SUBMIT_ENABLED=false`.
6. AI assessor (Claude, `ai_assessor.py`): classification + policy-alignment + rationale attached to the response for audit logging. Advisory only — its output never feeds `should_submit_tx`, and evidence content is delimited/length-capped in the prompt to contain injection.

### Evidence integrity

Evidence is JSON pinned via Pinata as **CIDv1 / raw codec / sha2-256** (`bafkr…`).
The web `/api/pin` route enforces this for `kind: "evidence"`. The resolver
re-derives the CID from the fetched bytes (`resolver/src/evidence.py`); any
other CID format is unverifiable → HOLD. The on-chain `evidenceCID` string is
therefore a binding content commitment; history is preserved in
`EvidenceSubmitted` events.

## Security model

- **Resolver blast radius**: can only move an escrow's funds to that escrow's buyer or seller, in valid states. Key rotation = `setResolver` by owner (2-step owner transfer).
- **Liveness failure**: if CRE/resolver die, buyers can always `release()`; nothing auto-moves. Alerts (`ops/alerts/escrow_alerts.yml`) page on resolver downtime, stuck disputes, signer gas floor, indexer lag.
- **Dispute abuse**: disputing only freezes auto-release; refunds require valid evidence + seller inactivity. Dispute bonds are deferred (P2) pending observed abuse.
- **Token risk**: whitelist-only ERC-20s; balance-delta check rejects fee-on-transfer; blocklist recipients degrade to pull-payment.
- **Admin risk**: fee hard cap in bytecode; pause cannot trap funds; treasury/resolver changes are owner-gated and evented.
- Known residual risks: IPFS evidence is public (no PII; encrypted evidence is P2), category/metadata content is unmoderated (P1 UI-level reporting).

## Testing

- `contracts/test/EscrowMarket.t.sol` — 65 unit tests (every revert branch, events, pause semantics, payout fallbacks, reentrancy).
- `contracts/test/EscrowMarket.fuzz.t.sol` — fee-split exactness over full ranges, refund wholeness, deadline non-overlap, stranger access, ERC-20 round trips.
- `contracts/test/Invariants.t.sol` + `handlers/MarketHandler.sol` — exact per-token solvency (`balance == Σ open + Σ queued`), absorbing terminal states, exact treasury fee accrual, fee cap — driven by a randomized handler including an ETH-rejecting contract buyer.
- `resolver/tests/` — 32 tests: policy boundary table, CID vectors, API auth, indexer-fallback, AI failure isolation.
- CI: `.github/workflows/` — per-package checks, nightly deep fuzz, manual environment-gated Sepolia deploy.

## Deployment

- `contracts/script/Deploy.s.sol` — env-driven (resolver, treasury, windows, USDC whitelist), writes `contracts/deployments/<chainId>.json` consumed by web/indexer/resolver configs; supports 2-step ownership handover. `SeedListings.s.sol` seeds demo data.
- Targets **Base Sepolia only** (decision i); mainnet requires audit + the P2 checklist in PLAN.md.
- Runbook for the full end-to-end check: [E2E.md](./E2E.md).
