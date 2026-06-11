import { EscrowView } from "@/components/EscrowView";

export default async function EscrowPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <EscrowView id={id} />;
}
