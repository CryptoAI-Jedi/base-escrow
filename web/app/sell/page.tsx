"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { parseEther, parseUnits } from "viem";
import { useAccount, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { CATEGORIES, categoryHash, type Category } from "@/lib/categories";
import { escrowMarket, ZERO_ADDRESS } from "@/lib/contracts";
import { pinJson } from "@/lib/ipfs";

const USDC_ADDRESS = process.env.NEXT_PUBLIC_USDC_ADDRESS ?? "";

export default function SellPage() {
  const router = useRouter();
  const { address } = useAccount();

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [category, setCategory] = useState<Category>("other");
  const [token, setToken] = useState<"eth" | "usdc">("eth");
  const [price, setPrice] = useState("");
  const [pinning, setPinning] = useState(false);
  const [formError, setFormError] = useState("");

  const { writeContract, data: txHash, isPending, error: writeError } = useWriteContract();
  const { isLoading: confirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  useEffect(() => {
    if (isSuccess) router.push("/");
  }, [isSuccess, router]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    let priceUnits: bigint;
    try {
      priceUnits = token === "eth" ? parseEther(price) : parseUnits(price, 6);
      if (priceUnits <= BigInt(0)) throw new Error();
    } catch {
      setFormError("Enter a valid positive price.");
      return;
    }
    if (token === "usdc" && !USDC_ADDRESS) {
      setFormError("USDC address not configured (NEXT_PUBLIC_USDC_ADDRESS).");
      return;
    }

    setPinning(true);
    let cid: string;
    try {
      cid = await pinJson(
        { title, description, imageUrl: imageUrl || undefined },
        "metadata",
      );
    } catch (err) {
      setFormError(err instanceof Error ? err.message : "Pinning failed");
      setPinning(false);
      return;
    }
    setPinning(false);

    writeContract({
      ...escrowMarket,
      functionName: "createListing",
      args: [
        (token === "eth" ? ZERO_ADDRESS : USDC_ADDRESS) as `0x${string}`,
        priceUnits,
        categoryHash(category),
        cid,
      ],
    });
  };

  const busy = pinning || isPending || confirming;

  return (
    <div className="mx-auto max-w-xl">
      <h1 className="mb-6 text-2xl font-semibold">Create a listing</h1>
      <form
        onSubmit={onSubmit}
        className="space-y-4 rounded-xl border border-zinc-200 bg-white p-6"
      >
        <Field label="Title">
          <input
            required
            maxLength={80}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            placeholder="Mechanical keyboard, barely used"
          />
        </Field>

        <Field label="Description">
          <textarea
            required
            rows={4}
            maxLength={2000}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            placeholder="Condition, shipping, terms…"
          />
        </Field>

        <Field label="Image URL (optional)">
          <input
            type="url"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            placeholder="https://…"
          />
        </Field>

        <div className="grid grid-cols-3 gap-3">
          <Field label="Category">
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value as Category)}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            >
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Currency">
            <select
              value={token}
              onChange={(e) => setToken(e.target.value as "eth" | "usdc")}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
            >
              <option value="eth">ETH</option>
              <option value="usdc">USDC</option>
            </select>
          </Field>
          <Field label={`Price (${token.toUpperCase()})`}>
            <input
              required
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
              placeholder={token === "eth" ? "0.01" : "25.00"}
            />
          </Field>
        </div>

        <button
          type="submit"
          disabled={!address || busy}
          className="w-full rounded-lg bg-zinc-900 px-5 py-2.5 text-sm font-medium text-white transition enabled:hover:bg-zinc-700 disabled:opacity-40"
        >
          {!address
            ? "Connect wallet to sell"
            : pinning
              ? "Pinning metadata to IPFS…"
              : isPending || confirming
                ? "Confirming transaction…"
                : "Create listing"}
        </button>

        {(formError || writeError) && (
          <p className="text-sm text-rose-600">
            {formError || writeError?.message.split("\n")[0]}
          </p>
        )}
      </form>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-zinc-700">
        {label}
      </span>
      {children}
    </label>
  );
}
