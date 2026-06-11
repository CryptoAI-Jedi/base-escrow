"use client";

import { ConnectButton as RainbowConnectButton } from "@rainbow-me/rainbowkit";

export function ConnectButton() {
  return <RainbowConnectButton showBalance={false} chainStatus="icon" />;
}
