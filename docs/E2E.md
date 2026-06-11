# End-to-end runbook

Two procedures: the **local** loop (validated, repeatable in ~2 minutes) and
the **Base Sepolia** dry-run (requires funded keys + CRE registration).

Account keys below are anvil's well-known dev accounts — never use them on a
real network.

## A. Local loop (anvil) — validated

Roles: account0 = deployer/owner, account1 = resolver signer & demo seller,
account2 = treasury, account3 = buyer.

```bash
# 0. Start a local chain with Base Sepolia's chain id (mine-on-demand)
anvil --port 8546 --chain-id 84532 &

# 1. Deploy with short windows so deadlines pass in seconds
cd contracts
RESOLVER_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
TREASURY_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
RELEASE_WINDOW=3 SELLER_RESPONSE_WINDOW=3 \
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8546 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
export ADDR=$(python3 -c "import json; print(json.load(open('deployments/84532.json'))['escrowMarket'])")

# 2. Seed listings (as the resolver/seller account)
ESCROW_MARKET_ADDRESS=$ADDR forge script script/SeedListings.s.sol \
  --rpc-url http://127.0.0.1:8546 \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d --broadcast

# 3. Start the indexer (separate terminal)
cd ../indexer
PONDER_RPC_URL_84532=http://127.0.0.1:8546 ESCROW_MARKET_ADDRESS=$ADDR \
ESCROW_MARKET_START_BLOCK=0 npm run dev
# verify: curl -s -X POST http://127.0.0.1:42069/graphql \
#   -H 'Content-Type: application/json' \
#   -d '{"query":"{ escrows(where:{status_in:[\"FUNDED\",\"DISPUTED\"]}) { items { id status } } }"}'

# 4. Buyer buys listing 1 (escrow 1, FUNDED, 3s release window)
cast send $ADDR "buy(uint256)" 1 --value 0.001ether \
  --rpc-url http://127.0.0.1:8546 \
  --private-key 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6

# 5a. Dispute path: buyer opens a dispute with evidence before the deadline
cast send $ADDR "openDispute(uint256,string)" 1 "<bafkr... evidence CID>" \
  --rpc-url http://127.0.0.1:8546 --private-key 0x7c8521...b007a6
# (the web app's escrow page does this with a real Pinata-pinned CID)

# 5b. Timeout path: just wait >3s, then mine to advance chain time
sleep 4 && cast rpc evm_mine --rpc-url http://127.0.0.1:8546

# 6. Resolver: config + run one batch tick with the dev submitter enabled
cd ../resolver && cat > config/.env <<EOF
CHAIN_ID=84532
RPC_URL=http://127.0.0.1:8546
ESCROW_MARKET_ADDRESS=$ADDR
PONDER_GRAPHQL_URL=http://127.0.0.1:42069/graphql
RESOLVER_API_TOKEN=local-dev-token
RESOLVER_SUBMIT_ENABLED=true
RESOLVER_SIGNER_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
EOF
.venv/bin/python -m src.main
```

**Validated output** (timeout path):

```
[CHAIN] resolveRelease escrow=1 tx=cfb5aa25…f91186 status=1
[RESOLVED] escrow=1 action=RELEASE reason=AUTO_RELEASE_TIMEOUT tx=cfb5aa25…f91186
```

and with a disputed escrow carrying an unverifiable CID:

```
[SKIP] escrow=1 action=HOLD reason=EVIDENCE_HASH_MISMATCH
```

Also validated: indexer GraphQL returns listings/escrows/sellerStats; resolver
falls back to the bounded on-chain scan when Ponder is down.

> Time-warp caveat: the policy clock is wall time, the contract uses
> `block.timestamp`. With `evm_increaseTime`-style warping they diverge —
> prefer short windows + real waiting (as above). Remember anvil only advances
> chain time when a block is mined (`cast rpc evm_mine`).

## B. Base Sepolia dry-run — pending (needs keys + CRE registration)

1. **Deploy**: run the `deploy-testnet` GitHub Action (environment `base-sepolia`
   with `DEPLOYER_PRIVATE_KEY`, `BASE_SEPOLIA_RPC_URL`, `BASESCAN_API_KEY`
   secrets and `RESOLVER_ADDRESS`/`TREASURY_ADDRESS`/`USDC_ADDRESS` vars), or
   locally with the same env via `forge script ... --verify`.
   USDC (Base Sepolia): `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (verify against Circle docs).
2. **Indexer**: set `ESCROW_MARKET_ADDRESS` + `ESCROW_MARKET_START_BLOCK` (deploy
   block from `deployments/84532.json`), run `ponder start`.
3. **Resolver**: fill `resolver/config/.env` (keep `RESOLVER_SUBMIT_ENABLED=false`),
   run uvicorn; confirm `/health` and `/metrics`.
4. **CRE**: register `cre/triggers/*.yaml` + `cre/workflows/dispute_resolution.workflow.yaml`
   with env (`ESCROW_MARKET_ADDRESS`, `RESOLVER_BASE_URL`, `RESOLVER_API_TOKEN`,
   `RESOLVER_SIGNER_PRIVATE_KEY` = the address passed as `RESOLVER_ADDRESS` at deploy).
5. **Web**: set `web/.env.local` (address, Ponder URL, WalletConnect id, Pinata JWT), deploy to Vercel.
6. **Exercise**: create listing → buy → open dispute with evidence from the UI →
   watch the CRE run: trigger fires → `/resolve` decision → on-chain
   `resolveRefund`/`resolveRelease` → indexer + UI show the terminal state.
7. **Record evidence**: contract address, tx hashes, trigger/workflow run logs →
   append here.
