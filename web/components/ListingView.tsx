"use client";

import { useQuery } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { decodeEventLog, erc20Abi } from "viem";
import {
  useAccount,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";

import { categoryFromHash } from "@/lib/categories";
import { escrowMarket, ZERO_ADDRESS } from "@/lib/contracts";
import { formatAmount, shortAddress } from "@/lib/format";
import { LISTING_QUERY, ponder, type ListingRow } from "@/lib/graphql";
import { fetchListingMetadata } from "@/lib/ipfs";

export function ListingView({ id }: { id: string }) {
  const router = useRouter();
  const { address } = useAccount();

  const { data, isLoading } = useQuery({
    queryKey: ["listing", id],
    queryFn: () =>
      ponder.request<{ listing: ListingRow | null }>(LISTING_QUERY, { id }),
  });
  const listing = data?.listing ?? null;

  const { data: meta } = useQuery({
    queryKey: ["metadata", listing?.metadataCID],
    queryFn: () => fetchListingMetadata(listing!.metadataCID),
    enabled: !!listing,
    staleTime: Infinity,
  });

  const {
    writeContract,
    data: txHash,
    isPending,
    error: writeError,
  } = useWriteContract();
  const { data: receipt, isLoading: confirming } =
    useWaitForTransactionReceipt({ hash: txHash });

  // After a confirmed buy, jump to the new escrow page.
  useEffect(() => {
    if (!receipt) return;
    for (const log of receipt.logs) {
      try {
        const parsed = decodeEventLog({
          abi: escrowMarket.abi,
          data: log.data,
          topics: log.topics,
        });
        if (parsed.eventName === "EscrowCreated") {
          const escrowId = (parsed.args as { escrowId: bigint }).escrowId;
          router.push(`/escrow/${escrowId}`);
          return;
        }
      } catch {
        // not our event
      }
    }
  }, [receipt, router]);

  if (isLoading) return <p className="text-zinc-500">Loading listing…</p>;
  if (!listing) return <p className="text-zinc-500">Listing not found.</p>;

  const isEth = listing.token.toLowerCase() === ZERO_ADDRESS;
  const isSeller = address?.toLowerCase() === listing.seller.toLowerCase();

  const onBuy = () => {
    if (isEth) {
      writeContract({
        ...escrowMarket,
        functionName: "buy",
        args: [BigInt(listing.id)],
        value: BigInt(listing.price),
      });
    } else {
      // ERC-20: approve then buy. MVP keeps it as two explicit transactions.
      writeContract(
        {
          abi: erc20Abi,
          address: listing.token as `0x${string}`,
          functionName: "approve",
          args: [escrowMarket.address, BigInt(listing.price)],
        },
        {
          onSuccess: () =>
            writeContract({
              ...escrowMarket,
              functionName: "buyERC20",
              args: [BigInt(listing.id)],
            }),
        },
      );
    }
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="rounded-xl border border-zinc-200 bg-white p-6">
        <div className="mb-3 flex items-center justify-between">
          <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600">
            {categoryFromHash(listing.category)}
          </span>
          <span className="text-xs text-zinc-400">Listing #{listing.id}</span>
        </div>

        {meta?.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={meta.imageUrl}
            alt={meta?.title ?? ""}
            className="mb-4 max-h-80 w-full rounded-lg object-cover"
          />
        ) : null}

        <h1 className="text-2xl font-semibold">
          {meta?.title ?? `Listing #${listing.id}`}
        </h1>
        <p className="mt-2 whitespace-pre-wrap text-zinc-600">
          {meta?.description ?? "No description available."}
        </p>

        <dl className="mt-4 space-y-1 text-sm text-zinc-500">
          <div className="flex gap-2">
            <dt>Seller:</dt>
            <dd className="font-mono">{shortAddress(listing.seller)}</dd>
          </div>
          <div className="flex gap-2">
            <dt>Payment:</dt>
            <dd>{isEth ? "Native ETH" : "USDC"}</dd>
          </div>
        </dl>

        <div className="mt-6 flex items-center justify-between border-t border-zinc-100 pt-4">
          <span className="text-xl font-semibold">
            {formatAmount(listing.price, listing.token)}
          </span>
          <button
            onClick={onBuy}
            disabled={!address || isSeller || isPending || confirming}
            className="rounded-lg bg-zinc-900 px-5 py-2 text-sm font-medium text-white transition enabled:hover:bg-zinc-700 disabled:opacity-40"
          >
            {!address
              ? "Connect wallet to buy"
              : isSeller
                ? "This is your listing"
                : isPending || confirming
                  ? "Confirming…"
                  : "Buy with escrow"}
          </button>
        </div>

        {writeError ? (
          <p className="mt-3 text-sm text-rose-600">
            {writeError.message.split("\n")[0]}
          </p>
        ) : null}

        <p className="mt-4 text-xs text-zinc-400">
          Funds are held in escrow. Release them after delivery, or open a
          dispute before the release deadline — an automated resolver settles
          disputes from submitted evidence.
        </p>
      </div>
    </div>
  );
}
