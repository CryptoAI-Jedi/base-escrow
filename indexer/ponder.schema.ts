import { onchainTable } from "ponder";

export const listing = onchainTable("listing", (t) => ({
  id: t.bigint().primaryKey(),
  seller: t.hex().notNull(),
  token: t.hex().notNull(), // zero address = native ETH
  price: t.bigint().notNull(),
  category: t.hex().notNull(), // keccak256 of canonical category slug
  metadataCID: t.text().notNull(),
  active: t.boolean().notNull(),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const escrow = onchainTable("escrow", (t) => ({
  id: t.bigint().primaryKey(),
  listingId: t.bigint().notNull(),
  buyer: t.hex().notNull(),
  seller: t.hex().notNull(),
  token: t.hex().notNull(),
  amount: t.bigint().notNull(),
  feeAmount: t.bigint().notNull(),
  status: t.text().notNull(), // FUNDED | DISPUTED | RELEASED | REFUNDED
  releaseDeadline: t.bigint().notNull(),
  sellerResponseDeadline: t.bigint(), // null until disputed
  evidenceCID: t.text(),
  disputedBy: t.hex(),
  resolvedReason: t.hex(), // bytes32 reason code from Resolved (resolver path only)
  createdAt: t.bigint().notNull(),
  resolvedAt: t.bigint(),
}));

export const evidenceSubmission = onchainTable("evidence_submission", (t) => ({
  id: t.text().primaryKey(), // `${escrowId}-${logIndex}`
  escrowId: t.bigint().notNull(),
  by: t.hex().notNull(),
  cid: t.text().notNull(),
  submittedAt: t.bigint().notNull(),
}));

// Aggregates powering seller profiles and rankings (P1 adds review scores).
export const sellerStats = onchainTable("seller_stats", (t) => ({
  id: t.hex().primaryKey(), // seller address
  listingsCreated: t.bigint().notNull(),
  salesReleased: t.bigint().notNull(),
  refunds: t.bigint().notNull(),
  disputes: t.bigint().notNull(),
}));
