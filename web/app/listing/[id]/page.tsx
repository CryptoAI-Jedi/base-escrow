import { ListingView } from "@/components/ListingView";

export default async function ListingPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <ListingView id={id} />;
}
