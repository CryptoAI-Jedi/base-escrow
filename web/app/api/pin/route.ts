import { NextRequest, NextResponse } from "next/server";

const PINATA_JWT = process.env.PINATA_JWT ?? "";
const MAX_PAYLOAD_BYTES = 64 * 1024;

/** Pin JSON to IPFS via Pinata (JWT stays server-side).
 *
 * kind: "evidence" pins MUST come back as CIDv1/raw/sha2-256 ("bafkr...") —
 * that's the only format the resolver can re-derive and verify. Listing
 * metadata has no such constraint. */
export async function POST(req: NextRequest) {
  if (!PINATA_JWT) {
    return NextResponse.json(
      { error: "PINATA_JWT not configured on the server" },
      { status: 500 },
    );
  }

  let body: { payload?: unknown; kind?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (body.payload === undefined || !["metadata", "evidence"].includes(body.kind ?? "")) {
    return NextResponse.json(
      { error: "Expected { payload, kind: 'metadata' | 'evidence' }" },
      { status: 400 },
    );
  }

  const content = JSON.stringify(body.payload);
  if (content.length > MAX_PAYLOAD_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }

  // Upload as a file with cidVersion 1 so small JSON blobs come back as raw
  // single-block CIDs ("bafkr..."), which the resolver can verify.
  const form = new FormData();
  form.append(
    "file",
    new Blob([content], { type: "application/json" }),
    body.kind === "evidence" ? "evidence.json" : "metadata.json",
  );
  form.append("pinataOptions", JSON.stringify({ cidVersion: 1 }));

  const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: { Authorization: `Bearer ${PINATA_JWT}` },
    body: form,
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    return NextResponse.json(
      { error: `Pinata error (${res.status}): ${detail.slice(0, 200)}` },
      { status: 502 },
    );
  }

  const { IpfsHash } = (await res.json()) as { IpfsHash: string };

  if (body.kind === "evidence" && !IpfsHash.startsWith("bafkr")) {
    return NextResponse.json(
      {
        error: `Evidence pin returned a non-raw CID (${IpfsHash}); the resolver cannot verify it`,
      },
      { status: 502 },
    );
  }

  return NextResponse.json({ cid: IpfsHash });
}
