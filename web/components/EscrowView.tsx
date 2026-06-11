"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";

import { ESCROW_STATUS, escrowMarket } from "@/lib/contracts";
import {
  formatAmount,
  formatDeadline,
  shortAddress,
  STATUS_STYLES,
} from "@/lib/format";
import { ipfsUrl, pinJson } from "@/lib/ipfs";

export function EscrowView({ id }: { id: string }) {
  const escrowId = BigInt(id);
  const { address } = useAccount();
  const queryClient = useQueryClient();

  // Read directly from the chain: the escrow page is the source of truth for
  // actions, so it must not lag behind the indexer.
  const { data: escrow, refetch } = useReadContract({
    ...escrowMarket,
    functionName: "getEscrow",
    args: [escrowId],
  });

  const { writeContract, data: txHash, isPending, error: writeError } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed } =
    useWaitForTransactionReceipt({ hash: txHash });

  // Refresh chain + indexer state once an action lands.
  useEffect(() => {
    if (confirmed) {
      refetch();
      queryClient.invalidateQueries();
    }
  }, [confirmed, refetch, queryClient]);

  const [evidenceText, setEvidenceText] = useState("");
  const [pinning, setPinning] = useState(false);
  const [actionError, setActionError] = useState("");
  const [nowSeconds] = useState(() => Math.floor(Date.now() / 1000));

  if (!escrow) return <p className="text-zinc-500">Loading escrow…</p>;

  const status = ESCROW_STATUS[escrow.status] ?? "UNKNOWN";
  if (status === "NONE") {
    return <p className="text-zinc-500">Escrow #{id} does not exist.</p>;
  }

  const me = address?.toLowerCase();
  const isBuyer = me === escrow.buyer.toLowerCase();
  const isSeller = me === escrow.seller.toLowerCase();
  const isParty = isBuyer || isSeller;
  const open = status === "FUNDED" || status === "DISPUTED";
  const canDispute =
    isParty && status === "FUNDED" && nowSeconds < Number(escrow.releaseDeadline);

  const busy = isPending || confirming || pinning;

  const submitWithEvidence = async (
    fn: "openDispute" | "submitEvidence",
  ) => {
    setActionError("");
    if (!evidenceText.trim()) {
      setActionError("Describe the issue — it will be pinned as evidence.");
      return;
    }
    setPinning(true);
    try {
      const cid = await pinJson(
        {
          escrowId: id,
          author: address,
          statement: evidenceText.trim(),
          submittedAt: new Date().toISOString(),
        },
        "evidence",
      );
      writeContract({
        ...escrowMarket,
        functionName: fn,
        args: [escrowId, cid],
      });
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Evidence pin failed");
    } finally {
      setPinning(false);
    }
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="rounded-xl border border-zinc-200 bg-white p-6">
        <div className="mb-4 flex items-center justify-between">
          <h1 className="text-2xl font-semibold">Escrow #{id}</h1>
          <span
            className={`rounded-full px-3 py-1 text-xs font-medium ${STATUS_STYLES[status] ?? "bg-zinc-100 text-zinc-700"}`}
          >
            {status}
          </span>
        </div>

        <dl className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
          <Item label="Amount">{formatAmount(escrow.amount, escrow.token)}</Item>
          <Item label="Listing">#{escrow.listingId.toString()}</Item>
          <Item label="Buyer">
            <span className="font-mono">{shortAddress(escrow.buyer)}</span>
            {isBuyer ? " (you)" : ""}
          </Item>
          <Item label="Seller">
            <span className="font-mono">{shortAddress(escrow.seller)}</span>
            {isSeller ? " (you)" : ""}
          </Item>
          <Item label="Auto-release after">
            {formatDeadline(escrow.releaseDeadline)}
          </Item>
          {status === "DISPUTED" && (
            <Item label="Seller must respond by">
              {formatDeadline(escrow.sellerResponseDeadline)}
            </Item>
          )}
          {escrow.disputedBy !==
            "0x0000000000000000000000000000000000000000" && (
            <Item label="Disputed by">
              <span className="font-mono">{shortAddress(escrow.disputedBy)}</span>
            </Item>
          )}
          {escrow.evidenceCID ? (
            <Item label="Latest evidence">
              <a
                href={ipfsUrl(escrow.evidenceCID)}
                target="_blank"
                rel="noreferrer"
                className="text-blue-600 underline"
              >
                {escrow.evidenceCID.slice(0, 16)}…
              </a>
            </Item>
          ) : null}
        </dl>

        {open && isParty ? (
          <div className="mt-6 space-y-4 border-t border-zinc-100 pt-4">
            {isBuyer && (
              <button
                onClick={() => {
                  setActionError("");
                  writeContract({
                    ...escrowMarket,
                    functionName: "release",
                    args: [escrowId],
                  });
                }}
                disabled={busy}
                className="w-full rounded-lg bg-emerald-600 px-5 py-2.5 text-sm font-medium text-white transition enabled:hover:bg-emerald-500 disabled:opacity-40"
              >
                Release funds to seller
              </button>
            )}

            {(canDispute || status === "DISPUTED") && (
              <div>
                <textarea
                  rows={3}
                  value={evidenceText}
                  onChange={(e) => setEvidenceText(e.target.value)}
                  placeholder={
                    status === "DISPUTED"
                      ? "Add a statement or rebuttal (pinned to IPFS as evidence)…"
                      : "Describe the problem (pinned to IPFS as evidence)…"
                  }
                  className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
                <button
                  onClick={() =>
                    submitWithEvidence(
                      status === "DISPUTED" ? "submitEvidence" : "openDispute",
                    )
                  }
                  disabled={busy}
                  className="mt-2 w-full rounded-lg bg-amber-600 px-5 py-2.5 text-sm font-medium text-white transition enabled:hover:bg-amber-500 disabled:opacity-40"
                >
                  {pinning
                    ? "Pinning evidence…"
                    : busy
                      ? "Confirming…"
                      : status === "DISPUTED"
                        ? "Submit evidence"
                        : "Open dispute"}
                </button>
              </div>
            )}
          </div>
        ) : null}

        {(actionError || writeError) && (
          <p className="mt-3 text-sm text-rose-600">
            {actionError || writeError?.message.split("\n")[0]}
          </p>
        )}

        <p className="mt-4 text-xs text-zinc-400">
          {status === "FUNDED" &&
            "Funds auto-release to the seller after the deadline unless a dispute is opened."}
          {status === "DISPUTED" &&
            "An automated resolver verifies the evidence; with valid evidence and no seller response by the deadline, the buyer is refunded."}
          {(status === "RELEASED" || status === "REFUNDED") &&
            "This escrow is settled and can no longer change."}
        </p>
      </div>
    </div>
  );
}

function Item({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <dt className="text-zinc-400">{label}</dt>
      <dd className="text-zinc-800">{children}</dd>
    </div>
  );
}
