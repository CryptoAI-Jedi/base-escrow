"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useAccount } from "wagmi";

import { formatAmount, shortAddress, STATUS_STYLES } from "@/lib/format";
import { MY_TRADES_QUERY, ponder, type EscrowRow } from "@/lib/graphql";

type TradesResult = {
  purchases: { items: EscrowRow[] };
  sales: { items: EscrowRow[] };
};

export default function MyTradesPage() {
  const { address } = useAccount();

  const { data, isLoading } = useQuery({
    queryKey: ["myTrades", address],
    queryFn: () =>
      ponder.request<TradesResult>(MY_TRADES_QUERY, {
        address: address!.toLowerCase(),
      }),
    enabled: !!address,
    refetchInterval: 15_000,
  });

  if (!address) {
    return (
      <p className="text-zinc-500">Connect your wallet to see your trades.</p>
    );
  }
  if (isLoading) return <p className="text-zinc-500">Loading trades…</p>;

  return (
    <div className="space-y-10">
      <TradeTable
        title="Purchases"
        rows={data?.purchases.items ?? []}
        counterpartyLabel="Seller"
        counterparty={(e) => e.seller}
      />
      <TradeTable
        title="Sales"
        rows={data?.sales.items ?? []}
        counterpartyLabel="Buyer"
        counterparty={(e) => e.buyer}
      />
    </div>
  );
}

function TradeTable({
  title,
  rows,
  counterpartyLabel,
  counterparty,
}: {
  title: string;
  rows: EscrowRow[];
  counterpartyLabel: string;
  counterparty: (e: EscrowRow) => string;
}) {
  return (
    <section>
      <h2 className="mb-3 text-xl font-semibold">{title}</h2>
      {rows.length === 0 ? (
        <p className="text-sm text-zinc-500">Nothing here yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-zinc-200 bg-white">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-100 text-left text-xs uppercase text-zinc-400">
                <th className="px-4 py-2">Escrow</th>
                <th className="px-4 py-2">Amount</th>
                <th className="px-4 py-2">{counterpartyLabel}</th>
                <th className="px-4 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((e) => (
                <tr key={e.id} className="border-b border-zinc-50">
                  <td className="px-4 py-2">
                    <Link
                      href={`/escrow/${e.id}`}
                      className="text-blue-600 underline"
                    >
                      #{e.id}
                    </Link>
                  </td>
                  <td className="px-4 py-2">
                    {formatAmount(e.amount, e.token)}
                  </td>
                  <td className="px-4 py-2 font-mono">
                    {shortAddress(counterparty(e))}
                  </td>
                  <td className="px-4 py-2">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_STYLES[e.status] ?? "bg-zinc-100 text-zinc-700"}`}
                    >
                      {e.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
