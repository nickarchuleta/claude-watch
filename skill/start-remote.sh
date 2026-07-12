#!/usr/bin/env bash
# Start Agent Watch bridge with optional remote access (Tailscale or Cloudflare).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$ROOT/bridge"
PORT="${AGENT_WATCH_PORT:-7860}"
MODE="${1:-tailscale}"

start_bridge() {
  cd "$BRIDGE_DIR"
  if [[ ! -d node_modules ]]; then
    npm install
  fi
  node server.js
}

case "$MODE" in
  local)
    echo "Starting bridge on LAN only (Bonjour + local IP)..."
    exec start_bridge
    ;;
  tailscale)
    if ! command -v tailscale >/dev/null 2>&1; then
      echo "Tailscale not installed. Install from https://tailscale.com/download or run: $0 cloudflare" >&2
      exit 1
    fi
    echo "Starting bridge, then exposing via Tailscale Serve on your tailnet..."
    echo "On iPhone: pair using your Mac Tailscale hostname or 100.x IP (Settings shows URL in bridge banner)."
    start_bridge &
    BRIDGE_PID=$!
    sleep 2
    tailscale serve --bg --https=443 "http://127.0.0.1:${PORT}" 2>/dev/null || \
      tailscale serve --bg "http://127.0.0.1:${PORT}"
    echo ""
    echo "Tailscale URL: https://$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Self',{}).get('DNSName','').rstrip('.'))" 2>/dev/null || tailscale ip -4)"
    echo "Bridge PID: $BRIDGE_PID — Ctrl+C stops bridge; run 'tailscale serve reset' to remove serve."
    wait "$BRIDGE_PID"
    ;;
  cloudflare)
    if ! command -v cloudflared >/dev/null 2>&1; then
      echo "cloudflared not installed. brew install cloudflared" >&2
      exit 1
    fi
    echo "Starting bridge + Cloudflare quick tunnel (public URL — use pairing code!)"
    start_bridge &
    BRIDGE_PID=$!
    sleep 2
    cloudflared tunnel --url "http://127.0.0.1:${PORT}"
    kill "$BRIDGE_PID" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {local|tailscale|cloudflare}" >&2
    echo "  local      — LAN only (default upstream behavior)" >&2
    echo "  tailscale  — expose bridge on your Tailscale tailnet (recommended)" >&2
    echo "  cloudflare — temporary public URL via Cloudflare Tunnel" >&2
    exit 2
    ;;
esac