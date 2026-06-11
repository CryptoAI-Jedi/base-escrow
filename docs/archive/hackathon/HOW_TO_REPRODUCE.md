### How to Reproduce in < 5 min

1) **Clone + setup**
```bash
git clone https://github.com/CryptoAI-Jedi/base-escrow.git
cd base-escrow
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2) **Create env files**

`env.deploy`
```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<ARBITER_PRIVATE_KEY>
BUYER_ADDRESS=0x<BUYER_ADDRESS>
SELLER_ADDRESS=0x<SELLER_ADDRESS>
ARBITER_ADDRESS=0x<ARBITER_ADDRESS>
```

`env.buyer`
```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<BUYER_PRIVATE_KEY>
```

`env.seller`
```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<SELLER_PRIVATE_KEY>
```

`env.arbiter`
```env
RPC_URL=https://sepolia.base.org
CHAIN_ID=84532
PRIVATE_KEY=0x<ARBITER_PRIVATE_KEY>
```

3) **Deploy fresh contract**
```bash
cp env.deploy .env
python scripts/deploy.py
cat out/Escrow.address.txt
```

4) **Fund buyer on Base Sepolia**
Send test ETH to buyer wallet (enough for deposit + gas).

5) **Run full dispute/refund proof**
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

**Expected final output**
- `status: REFUNDED`
- `amount: 0 ETH (0 wei)`

**Optional happy path (fresh deploy)**
```bash
cp env.deploy .env
python scripts/deploy.py

./switch-role.sh buyer
python scripts/interact.py deposit --eth 0.0001
python scripts/interact.py release
python scripts/interact.py status
```

Expected:
- `status: RELEASED`
- `amount: 0 ETH (0 wei)`