### README — Test Evidence (Base Sepolia)

#### Deployment Info
- **Network:** Base Sepolia (`chainId: 84532`)
- **Contract:** `Escrow.vy` (Vyper `0.4.3`)
- **Latest deployed address:** `0xD7652A0e28085d0565af4B2F0b2f6901499042F8`
- **Previous deployed address:** `0x6BA7B788322A703104f139aa0bA38D38048f7CE7`
- **Role addresses:**
  - Buyer: `0x45FEB305467ee1130Ae6049B4a4C8B798Fa2d2B4`
  - Seller: `0x6A18650859bb60631C940C03353C8EE9554A3790`
  - Arbiter / Resolver Signer: `0xd51812F502BDc565A0555257eF980e3199FC255c`

#### State Machine
- `0 = AWAITING_DEPOSIT`
- `1 = FUNDED`
- `2 = RELEASED`
- `3 = REFUNDED`
- `4 = DISPUTED`

#### Role Switching
```bash
./switch-role.sh buyer
./switch-role.sh seller
./switch-role.sh arbiter
```

---

#### CRE Resolver Demo Run (2026-03-07) — Live End-to-End with AI Assessment

This run demonstrates the full CRE dispute-resolution flow including AI-assisted assessment:
buyer deposits → seller disputes → CRE resolver reads on-chain state → policy evaluates → Claude AI assesses → resolver submits `refund()` on-chain autonomously.

**Contract:** `0xD7652A0e28085d0565af4B2F0b2f6901499042F8`

| Step | Actor | Action | Tx Hash | Status | Resulting State |
|---|---|---|---|---|---|
| Deploy | Arbiter | `deploy.py` | *(fresh deployment)* | `1` | `AWAITING_DEPOSIT` |
| Deposit | Buyer | `deposit --eth 0.0001` | *(captured in session)* | `1` | `FUNDED` |
| Mark Dispute | Seller | `mark_dispute` | *(captured in session)* | `1` | `DISPUTED` |
| CRE Resolver | Resolver API + `src.main` | `refund()` via web3 | `a214c58c25e291bb7b14e3329a4a42da12461d1067ba12ebf6068e3792260548` | `1` | `REFUNDED` |

**Resolver API response (with AI assessment):**
```json
{
  "escrow_id": "0xD7652A0e28085d0565af4B2F0b2f6901499042F8",
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

**Resolver batch runner output:**
```
[CHAIN] refund tx=a214c58c25e291bb7b14e3329a4a42da12461d1067ba12ebf6068e3792260548 status=1 reason=DISPUTED_ARBITER_REFUND
[RESOLVED] escrow=0xD7652A0e28085d0565af4B2F0b2f6901499042F8 action=REFUND reason=DISPUTED_ARBITER_REFUND tx=a214c58c25e291bb7b14e3329a4a42da12461d1067ba12ebf6068e3792260548
```

**Post-resolution status check:**
```
python scripts/interact.py status
→ status: REFUNDED
```

**AI Assessment layer notes:**
- Model: `claude-haiku-4-5-20251001` (non-blocking, advisory only)
- The deterministic policy engine always runs first and is always authoritative
- If the AI call fails for any reason (no API key, rate limit, parse error), the resolver returns the policy decision unchanged — `ai_assessment` is simply omitted from the response
- The AI layer adds structured dispute classification and policy alignment confirmation for audit/logging purposes

---

#### CRE Resolver Demo Run (Earlier — Contract `0x6BA7B788322A703104f139aa0bA38D38048f7CE7`)

| Step | Actor | Action | Tx Hash | Status | Resulting State |
|---|---|---|---|---|---|
| Deploy | Arbiter | `deploy.py` | `ae9b03591fc124236ada850e8ccb02116d63bc5a8492f86e64e5ca19b40e7784` | `1` | `AWAITING_DEPOSIT` |
| Deposit | Buyer | `deposit --eth 0.0001` | *(not captured)* | `1` | `FUNDED` |
| Mark Dispute | Seller | `mark_dispute` | `bbf8cbaca3183c4fb7bf6473feefb6a6ad5a219b7bf1cea72c98f79a2f78a428` | `1` | `DISPUTED` |
| CRE Resolver | Resolver API + `src.main` | `refund()` via web3 | `591b6f1de688ee436b42601d8256c473cc638a1b4a6c34429069efd168fe97ca` | `1` | `REFUNDED` |

---

#### Happy Path (Buyer releases to Seller)
```bash
./switch-role.sh buyer
python scripts/interact.py deposit --eth 0.0001
python scripts/interact.py release
python scripts/interact.py status
```

Expected terminal state:
- `status = RELEASED`
- `amount = 0`

---

#### Manual Dispute/Refund Path (Arbiter acts directly)
```bash
./switch-role.sh buyer
python scripts/interact.py deposit --eth 0.0001

./switch-role.sh seller
python scripts/interact.py mark_dispute

./switch-role.sh arbiter
python scripts/interact.py approve_refund
python scripts/interact.py refund

python scripts/interact.py status
```

Expected terminal state:
- `status = REFUNDED`
- `amount = 0`

---

#### Earlier Verified Transaction Evidence

Contract: `0x43F5cC8AF9c6dAD78Ebfd8d1700db40d52C82b70`

| Step | Role | Command | Tx Hash | Receipt Status | Expected State |
|---|---|---|---|---|---|
| Deposit | Buyer | `deposit --eth 0.0001` | `0x7e9adf8987d31495a1f98a454d54d786e11fad246fcadac905973a15aac986f8` | `1` | `FUNDED` |
| Approve Refund | Arbiter | `approve_refund` | `0x7f18b968be27630079c052901a77c8241c2441b3b751db4f821a7c27c70f0112` | `1` | `DISPUTED` |
| Refund | Arbiter | `refund` | `0x2f4ef6fdb82daf17f42271fc042f5674c72b2b54f58c5ac9f37a4a72f9441d2b` | `1` | `REFUNDED` |

> Note: If a transaction shows `replacement transaction underpriced`, wait briefly and resend with higher fee settings.

---

#### Quick Verification Commands
```bash
python scripts/interact.py status
cat out/Escrow.address.txt
```

#### Security/Operational Notes
- Non-reentrancy lock used on fund-moving functions.
- Role-gated actions:
  - Buyer only: `deposit`
  - Buyer/Arbiter: `release`
  - Seller/Buyer: `mark_dispute`
  - Arbiter only: `approve_refund`, `refund`
- Secrets are excluded from git (`env.*` in `.gitignore`).

---
