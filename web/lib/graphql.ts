import { GraphQLClient, gql } from "graphql-request";

const PONDER_URL =
  process.env.NEXT_PUBLIC_PONDER_URL ?? "http://127.0.0.1:42069/graphql";

export const ponder = new GraphQLClient(PONDER_URL);

export type ListingRow = {
  id: string;
  seller: string;
  token: string;
  price: string;
  category: string;
  metadataCID: string;
  active: boolean;
  createdAt: string;
};

export type EscrowRow = {
  id: string;
  listingId: string;
  buyer: string;
  seller: string;
  token: string;
  amount: string;
  feeAmount: string;
  status: string;
  releaseDeadline: string;
  sellerResponseDeadline: string | null;
  evidenceCID: string | null;
  disputedBy: string | null;
  resolvedReason: string | null;
  createdAt: string;
};

export const LISTINGS_QUERY = gql`
  query Listings($category: String) {
    listings(
      where: { active: true }
      orderBy: "createdAt"
      orderDirection: "desc"
      limit: 100
    ) {
      items {
        id
        seller
        token
        price
        category
        metadataCID
        active
        createdAt
      }
    }
  }
`;

export const LISTING_QUERY = gql`
  query Listing($id: BigInt!) {
    listing(id: $id) {
      id
      seller
      token
      price
      category
      metadataCID
      active
      createdAt
    }
  }
`;

export const ESCROW_QUERY = gql`
  query Escrow($id: BigInt!) {
    escrow(id: $id) {
      id
      listingId
      buyer
      seller
      token
      amount
      feeAmount
      status
      releaseDeadline
      sellerResponseDeadline
      evidenceCID
      disputedBy
      resolvedReason
      createdAt
    }
  }
`;

export const MY_TRADES_QUERY = gql`
  query MyTrades($address: String!) {
    purchases: escrows(
      where: { buyer: $address }
      orderBy: "createdAt"
      orderDirection: "desc"
      limit: 100
    ) {
      items {
        id
        listingId
        seller
        buyer
        token
        amount
        status
        releaseDeadline
        createdAt
      }
    }
    sales: escrows(
      where: { seller: $address }
      orderBy: "createdAt"
      orderDirection: "desc"
      limit: 100
    ) {
      items {
        id
        listingId
        seller
        buyer
        token
        amount
        status
        releaseDeadline
        createdAt
      }
    }
  }
`;
