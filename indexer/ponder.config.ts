import { createConfig } from "ponder";

import { EscrowMarketAbi } from "./abis/EscrowMarket";

export default createConfig({
  chains: {
    baseSepolia: {
      id: 84532,
      rpc: process.env.PONDER_RPC_URL_84532 ?? "https://sepolia.base.org",
    },
  },
  contracts: {
    EscrowMarket: {
      chain: "baseSepolia",
      abi: EscrowMarketAbi,
      address: (process.env.ESCROW_MARKET_ADDRESS ??
        "0x0000000000000000000000000000000000000000") as `0x${string}`,
      startBlock: Number(process.env.ESCROW_MARKET_START_BLOCK ?? 0),
    },
  },
});
