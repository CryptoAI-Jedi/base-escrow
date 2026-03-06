#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"

if [[ -z "$ROLE" ]]; then
  echo "Usage: $0 {buyer|seller|arbiter|status}"
  exit 1
fi

case "$ROLE" in
  buyer|seller|arbiter)
    SRC="env.${ROLE}"
    if [[ ! -f "$SRC" ]]; then
      echo "Error: $SRC not found in current directory: $(pwd)"
      exit 1
    fi

    cp "$SRC" .env
    chmod 600 .env || true

    # Show safe summary (never print private key)
    RPC_URL="$(grep '^RPC_URL=' .env | cut -d= -f2- || true)"
    CHAIN_ID="$(grep '^CHAIN_ID=' .env | cut -d= -f2- || true)"
    PK_LINE="$(grep '^PRIVATE_KEY=' .env | cut -d= -f2- || true)"

    if [[ -z "${PK_LINE}" ]]; then
      echo "Warning: PRIVATE_KEY missing in .env"
    fi

    PK_MASKED=""
    if [[ -n "${PK_LINE}" ]]; then
      # mask all but last 6 chars
      LEN=${#PK_LINE}
      if (( LEN > 6 )); then
        PK_MASKED="***${PK_LINE:LEN-6:6}"
      else
        PK_MASKED="***"
      fi
    fi

    echo "Switched role to: $ROLE"
    echo "RPC_URL: $RPC_URL"
    echo "CHAIN_ID: $CHAIN_ID"
    echo "PRIVATE_KEY: $PK_MASKED"
    echo
    echo "Next step example:"
    echo "  python scripts/interact.py status"
    ;;
  status)
    if [[ ! -f ".env" ]]; then
      echo "No active .env found."
      exit 1
    fi
    RPC_URL="$(grep '^RPC_URL=' .env | cut -d= -f2- || true)"
    CHAIN_ID="$(grep '^CHAIN_ID=' .env | cut -d= -f2- || true)"
    echo "Active .env detected"
    echo "RPC_URL: $RPC_URL"
    echo "CHAIN_ID: $CHAIN_ID"
    if grep -q '^PRIVATE_KEY=' .env; then
      echo "PRIVATE_KEY: set"
    else
      echo "PRIVATE_KEY: missing"
    fi
    ;;
  *)
    echo "Invalid role: $ROLE"
    echo "Usage: $0 {buyer|seller|arbiter|status}"
    exit 1
    ;;
esac