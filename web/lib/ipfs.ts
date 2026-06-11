export const IPFS_GATEWAY =
  process.env.NEXT_PUBLIC_IPFS_GATEWAY ?? "https://gateway.pinata.cloud";

export const ipfsUrl = (cid: string) => `${IPFS_GATEWAY}/ipfs/${cid}`;

export type ListingMetadata = {
  title: string;
  description: string;
  imageUrl?: string;
};

export async function fetchListingMetadata(
  cid: string,
): Promise<ListingMetadata | null> {
  try {
    const res = await fetch(ipfsUrl(cid), { cache: "force-cache" });
    if (!res.ok) return null;
    return (await res.json()) as ListingMetadata;
  } catch {
    return null;
  }
}

/** Pin a JSON payload via our server route (Pinata behind the scenes).
 *  Evidence pins MUST be CIDv1/raw/sha2-256 ("bafkr...") so the resolver can
 *  re-derive the hash — the route enforces this for kind: "evidence". */
export async function pinJson(
  payload: unknown,
  kind: "metadata" | "evidence",
): Promise<string> {
  const res = await fetch("/api/pin", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ payload, kind }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `Pin failed (${res.status})`);
  }
  const { cid } = (await res.json()) as { cid: string };
  return cid;
}
