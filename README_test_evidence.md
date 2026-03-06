### README — Test Evidence (Base Sepolia)

#### Deployment Info
- **Network:** Base Sepolia (`chainId: 84532`)
- **Contract:** `Escrow.vy` (Vyper `0.4.3`)
- **Latest deployed address:** `0x43F5cC8AF9c6dAD78Ebfd8d1700db40d52C82b70`
- **Role addresses:**
  - Buyer: `0x45FEB305467ee1130Ae6049B4a4C8B798Fa2d2B4`
  - Seller: `0x6A18650859bb60631C940C03353C8EE9554A3790`
  - Arbiter: `0xd51812F502BDc565A0555257eF980e3199FC255c`

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

#### Dispute/Refund Path (Seller disputes, Arbiter refunds)
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

#### Verified Transaction Evidence (example run)

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

