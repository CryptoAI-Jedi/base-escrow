"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";

import { ListingCard } from "@/components/ListingCard";
import { CATEGORIES, categoryHash } from "@/lib/categories";
import { LISTINGS_QUERY, ponder, type ListingRow } from "@/lib/graphql";

export default function BrowsePage() {
  const [category, setCategory] = useState<string>("all");
  const [search, setSearch] = useState("");

  const { data, isLoading, error } = useQuery({
    queryKey: ["listings"],
    queryFn: () =>
      ponder.request<{ listings: { items: ListingRow[] } }>(LISTINGS_QUERY),
    refetchInterval: 15_000,
  });

  const listings = (data?.listings.items ?? []).filter(
    (l) =>
      category === "all" ||
      l.category.toLowerCase() === categoryHash(category).toLowerCase(),
  );

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center gap-3">
        <h1 className="mr-auto text-2xl font-semibold">Browse listings</h1>
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search titles…"
          className="w-56 rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-sm"
        />
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-sm"
        >
          <option value="all">All categories</option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>

      {error ? (
        <p className="rounded-lg bg-rose-50 p-4 text-sm text-rose-700">
          Could not reach the indexer. Is Ponder running?
        </p>
      ) : null}
      {isLoading ? <p className="text-zinc-500">Loading listings…</p> : null}
      {!isLoading && listings.length === 0 && !error ? (
        <p className="text-zinc-500">
          No active listings yet — be the first to sell.
        </p>
      ) : null}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {listings.map((l) => (
          <ListingCard key={l.id} listing={l} search={search} />
        ))}
      </div>
    </div>
  );
}
