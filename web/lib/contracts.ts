import { escrowMarketAbi } from "./abi";

export const ESCROW_MARKET_ADDRESS = (process.env
  .NEXT_PUBLIC_ESCROW_MARKET_ADDRESS ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const escrowMarket = {
  address: ESCROW_MARKET_ADDRESS,
  abi: escrowMarketAbi,
} as const;

export const ZERO_ADDRESS =
  "0x0000000000000000000000000000000000000000" as const;

export const ESCROW_STATUS = [
  "NONE",
  "FUNDED",
  "DISPUTED",
  "RELEASED",
  "REFUNDED",
] as const;
