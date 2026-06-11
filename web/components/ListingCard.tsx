"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";

import { categoryFromHash } from "@/lib/categories";
import { formatAmount, shortAddress } from "@/lib/format";
import type { ListingRow } from "@/lib/graphql";
import { fetchListingMetadata } from "@/lib/ipfs";

export function ListingCard({
  listing,
  search = "",
}: {
  listing: ListingRow;
  search?: string;
}) {
  const { data: meta } = useQuery({
    queryKey: ["metadata", listing.metadataCID],
    queryFn: () => fetchListingMetadata(listing.metadataCID),
    staleTime: Infinity,
  });

  // Client-side title/description search over fetched metadata; category and
  // active filtering happen in the indexer query. (P1: server-side search.)
  const q = search.trim().toLowerCase();
  if (q) {
    const haystack = `${meta?.title ?? ""} ${meta?.description ?? ""}`.toLowerCase();
    if (!haystack.includes(q)) return null;
  }

  return (
    <Link
      href={`/listing/${listing.id}`}
      className="block rounded-xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-300 hover:shadow-sm"
    >
      <div className="mb-2 flex items-center justify-between">
        <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600">
          {categoryFromHash(listing.category)}
        </span>
        <span className="text-xs text-zinc-400">#{listing.id}</span>
      </div>
      {meta?.imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={meta.imageUrl}
          alt={meta?.title ?? `Listing ${listing.id}`}
          className="mb-3 h-36 w-full rounded-lg object-cover"
        />
      ) : (
        <div className="mb-3 flex h-36 w-full items-center justify-center rounded-lg bg-zinc-100 text-3xl">
          🛍️
        </div>
      )}
      <h3 className="truncate font-medium">
        {meta?.title ?? `Listing #${listing.id}`}
      </h3>
      <p className="mt-1 line-clamp-2 min-h-10 text-sm text-zinc-500">
        {meta?.description ?? "Metadata loading or unavailable"}
      </p>
      <div className="mt-3 flex items-center justify-between">
        <span className="font-semibold">
          {formatAmount(listing.price, listing.token)}
        </span>
        <span className="text-xs text-zinc-400">
          by {shortAddress(listing.seller)}
        </span>
      </div>
    </Link>
  );
}
