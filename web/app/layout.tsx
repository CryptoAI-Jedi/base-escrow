import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import "./globals.css";

import { ConnectButton } from "@/components/ConnectButton";
import { Providers } from "./providers";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Base Escrow Market",
  description:
    "Onchain marketplace on Base with escrowed payments and automated dispute resolution",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-zinc-50 text-zinc-900">
        <Providers>
          <header className="border-b border-zinc-200 bg-white">
            <div className="mx-auto flex max-w-6xl items-center justify-between gap-6 px-4 py-3">
              <Link href="/" className="text-lg font-semibold tracking-tight">
                Base Escrow Market
              </Link>
              <nav className="flex items-center gap-5 text-sm text-zinc-600">
                <Link href="/" className="hover:text-zinc-900">
                  Browse
                </Link>
                <Link href="/sell" className="hover:text-zinc-900">
                  Sell
                </Link>
                <Link href="/me" className="hover:text-zinc-900">
                  My trades
                </Link>
              </nav>
              <ConnectButton />
            </div>
          </header>
          <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
            {children}
          </main>
          <footer className="border-t border-zinc-200 bg-white py-4 text-center text-xs text-zinc-500">
            Base Sepolia testnet — not audited, do not use real funds
          </footer>
        </Providers>
      </body>
    </html>
  );
}
