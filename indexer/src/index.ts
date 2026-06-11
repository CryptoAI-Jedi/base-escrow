import { ponder } from "ponder:registry";
import { escrow, evidenceSubmission, listing, sellerStats } from "ponder:schema";

const ZERO_STATS = {
  listingsCreated: 0n,
  salesReleased: 0n,
  refunds: 0n,
  disputes: 0n,
};

// ---------------------------------------------------------------------------
// Listings
// ---------------------------------------------------------------------------

ponder.on("EscrowMarket:ListingCreated", async ({ event, context }) => {
  await context.db.insert(listing).values({
    id: event.args.listingId,
    seller: event.args.seller,
    token: event.args.token,
    price: event.args.price,
    category: event.args.category,
    metadataCID: event.args.metadataCID,
    active: true,
    createdAt: event.block.timestamp,
    updatedAt: event.block.timestamp,
  });

  await context.db
    .insert(sellerStats)
    .values({ id: event.args.seller, ...ZERO_STATS, listingsCreated: 1n })
    .onConflictDoUpdate((row) => ({ listingsCreated: row.listingsCreated + 1n }));
});

ponder.on("EscrowMarket:ListingUpdated", async ({ event, context }) => {
  await context.db.update(listing, { id: event.args.listingId }).set({
    price: event.args.price,
    metadataCID: event.args.metadataCID,
    updatedAt: event.block.timestamp,
  });
});

ponder.on("EscrowMarket:ListingCancelled", async ({ event, context }) => {
  await context.db.update(listing, { id: event.args.listingId }).set({
    active: false,
    updatedAt: event.block.timestamp,
  });
});

// ---------------------------------------------------------------------------
// Escrows
// ---------------------------------------------------------------------------

ponder.on("EscrowMarket:EscrowCreated", async ({ event, context }) => {
  await context.db.insert(escrow).values({
    id: event.args.escrowId,
    listingId: event.args.listingId,
    buyer: event.args.buyer,
    seller: event.args.seller,
    token: event.args.token,
    amount: event.args.amount,
    feeAmount: event.args.feeAmount,
    status: "FUNDED",
    releaseDeadline: event.args.releaseDeadline,
    createdAt: event.block.timestamp,
  });
});

ponder.on("EscrowMarket:DisputeOpened", async ({ event, context }) => {
  const row = await context.db.update(escrow, { id: event.args.escrowId }).set({
    status: "DISPUTED",
    sellerResponseDeadline: event.args.sellerResponseDeadline,
    evidenceCID: event.args.evidenceCID,
    disputedBy: event.args.by,
  });

  await context.db
    .insert(sellerStats)
    .values({ id: row.seller, ...ZERO_STATS, disputes: 1n })
    .onConflictDoUpdate((s) => ({ disputes: s.disputes + 1n }));
});

ponder.on("EscrowMarket:EvidenceSubmitted", async ({ event, context }) => {
  await context.db.insert(evidenceSubmission).values({
    id: `${event.args.escrowId}-${event.log.logIndex}`,
    escrowId: event.args.escrowId,
    by: event.args.by,
    cid: event.args.cid,
    submittedAt: event.block.timestamp,
  });

  await context.db.update(escrow, { id: event.args.escrowId }).set({
    evidenceCID: event.args.cid,
  });
});

// Resolved fires (resolver path only) in the same tx as Released/Refunded;
// it carries the audit reason code.
ponder.on("EscrowMarket:Resolved", async ({ event, context }) => {
  await context.db.update(escrow, { id: event.args.escrowId }).set({
    resolvedReason: event.args.reasonCode,
  });
});

ponder.on("EscrowMarket:Released", async ({ event, context }) => {
  const row = await context.db.update(escrow, { id: event.args.escrowId }).set({
    status: "RELEASED",
    resolvedAt: event.block.timestamp,
  });

  await context.db
    .insert(sellerStats)
    .values({ id: row.seller, ...ZERO_STATS, salesReleased: 1n })
    .onConflictDoUpdate((s) => ({ salesReleased: s.salesReleased + 1n }));
});

ponder.on("EscrowMarket:Refunded", async ({ event, context }) => {
  const row = await context.db.update(escrow, { id: event.args.escrowId }).set({
    status: "REFUNDED",
    resolvedAt: event.block.timestamp,
  });

  await context.db
    .insert(sellerStats)
    .values({ id: row.seller, ...ZERO_STATS, refunds: 1n })
    .onConflictDoUpdate((s) => ({ refunds: s.refunds + 1n }));
});
