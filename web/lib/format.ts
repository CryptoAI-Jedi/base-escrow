import { formatEther, formatUnits } from "viem";
import { ZERO_ADDRESS } from "./contracts";

export const shortAddress = (addr: string) =>
  `${addr.slice(0, 6)}…${addr.slice(-4)}`;

/** MVP token registry: native ETH + whitelisted USDC. */
export const tokenSymbol = (token: string) =>
  token.toLowerCase() === ZERO_ADDRESS ? "ETH" : "USDC";

export const formatAmount = (amount: bigint | string, token: string) => {
  const value = BigInt(amount);
  return token.toLowerCase() === ZERO_ADDRESS
    ? `${formatEther(value)} ETH`
    : `${formatUnits(value, 6)} USDC`;
};

export const formatDeadline = (ts: bigint | string | number) => {
  const date = new Date(Number(ts) * 1000);
  return date.toLocaleString();
};

export const STATUS_STYLES: Record<string, string> = {
  FUNDED: "bg-blue-100 text-blue-800",
  DISPUTED: "bg-amber-100 text-amber-800",
  RELEASED: "bg-emerald-100 text-emerald-800",
  REFUNDED: "bg-rose-100 text-rose-800",
};
