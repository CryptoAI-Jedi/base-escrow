
```markdown
# Base Escrow (Vyper) — Role-Based Escrow on Base Sepolia

A minimal, production-style escrow smart contract built with **Vyper** and tested on **Base Sepolia**.  
This project demonstrates a role-gated escrow flow with three actors:

- **Buyer**
- **Seller**
- **Arbiter**

It includes deployment + interaction scripts, role switching via env files, and reproducible test flows.

## Features

- Escrow state machine with explicit transitions
- Role-based access control for sensitive actions
- Deposit, release, dispute, approve-refund, refund flows
- Reproducible CLI test flow on Base Sepolia
- Scripted role switching (`buyer`, `seller`, `arbiter`)
- Non-reentrancy lock on fund-moving functions

## Tech Stack

- **Smart Contract:** Vyper (`0.4.3`)
- **Network:** Base Sepolia (`chainId: 84532`)
- **Scripts:** Python + Web3.py
- **Tooling:** dotenv env management

## Project Structure

```text
base-escrow/
├── contracts/
│   └── Escrow.vy
├── scripts/
│   ├── deploy.py
│   └── interact.py
├── out/
│   ├── Escrow.abi.json
│   ├── Escrow.bytecode.txt
│   └── Escrow.address.txt
├── switch-role.sh
├── requirements.txt
├── .gitignore
└── README.md
```

## State Machine

- `0 = AWAITING_DEPOSIT`
- `1 = FUNDED`
- `2 = RELEASED`
- `3 = REFUNDED`
- `4 = DISPUTED`

## Role Permissions (High Level)

- **Buyer**
  - `deposit()`
  - `release()` (if contract logic allows buyer release)
- **Seller / Buyer**
  - `mark_dispute()`
- **Arbiter**
  - `approve_refund()`
  - `refund()`
  - (and any arbiter-authorized releases depending on contract logic)

## Setup

### 1) Clone + environment

```bash
git clone https://github.com/CryptoAI-Jedi/base-escrow.git
cd base-escrow
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2) Create env files

Create four local env files (do **not** commit):

- `env.deploy`
- `env.buyer`
- `env.seller`
- `env.arbiter`

Example `env.deploy`:

```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<ARBITER_PRIVATE_KEY>
BUYER_ADDRESS=0x<BUYER_ADDRESS>
SELLER_ADDRESS=0x<SELLER_ADDRESS>
ARBITER_ADDRESS=0x<ARBITER_ADDRESS>
```

Example `env.buyer`:

```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<BUYER_PRIVATE_KEY>
```

Example `env.seller`:

```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<SELLER_PRIVATE_KEY>
```

Example `env.arbiter`:

```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<ARBITER_PRIVATE_KEY>
```

## Deploy

```bash
cp env.deploy .env
python scripts/deploy.py
cat out/Escrow.address.txt
```

## Role Switching

```bash
./switch-role.sh buyer
./switch-role.sh seller
./switch-role.sh arbiter
./switch-role.sh status
```

## Interaction Commands

```bash
python scripts/interact.py status
python scripts/interact.py deposit --eth 0.0001
python scripts/interact.py release
python scripts/interact.py mark_dispute
python scripts/interact.py approve_refund
python scripts/interact.py refund
```

## How to Reproduce in < 5 min

1. Setup venv + dependencies
2. Create env files for deploy + each role
3. Deploy fresh contract
4. Fund buyer wallet with Base Sepolia ETH
5. Run:

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

- `status: REFUNDED`
- `amount: 0 ETH (0 wei)`

## Notes / Troubleshooting

- If you see `replacement transaction underpriced`, wait 15–30 seconds and retry.
- If role actions revert, check current state first:
  ```bash
  python scripts/interact.py status
  ```
- Ensure you are in virtualenv before running Python scripts:
  ```bash
  source .venv/bin/activate
  ```

## Security Notes

- Never commit private keys or `.env` files.
- Keep `env.*` excluded in `.gitignore`.
- This is a testnet educational project; not audited for mainnet use.

## License

MIT (or your preferred license).
