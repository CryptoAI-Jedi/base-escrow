import { keccak256, toBytes } from "viem";

// Canonical category slugs — the contract stores keccak256(slug) as bytes32.
export const CATEGORIES = [
  "electronics",
  "collectibles",
  "fashion",
  "home",
  "services",
  "digital-goods",
  "other",
] as const;

export type Category = (typeof CATEGORIES)[number];

export const categoryHash = (slug: string): `0x${string}` =>
  keccak256(toBytes(slug));

const HASH_TO_SLUG = new Map<string, string>(
  CATEGORIES.map((slug) => [categoryHash(slug).toLowerCase(), slug]),
);

export const categoryFromHash = (hash: string): string =>
  HASH_TO_SLUG.get(hash.toLowerCase()) ?? "other";
