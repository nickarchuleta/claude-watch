#!/usr/bin/env bash
# Spawn a wrist profile on the running Agent Watch bridge.
# Usage: ./start-wrist.sh money|life [bridge_url] [pairing_code]
set -euo pipefail

PROFILE="${1:-}"
BRIDGE="${2:-http://127.0.0.1:7860}"
CODE="${3:-}"

if [[ -z "$PROFILE" ]]; then
  echo "Usage: $0 {money|life} [bridge_url] [pairing_code]" >&2
  echo "  money — Pi + OpenRouter (trading / backtest)" >&2
  echo "  life  — Claude Code (vault / life ops)" >&2
  exit 2
fi

if [[ -z "${AGENT_WATCH_TOKEN:-}" ]]; then
  if [[ -z "$CODE" ]]; then
    echo "Set AGENT_WATCH_TOKEN or pass pairing code as 3rd arg" >&2
    exit 1
  fi
  RESP=$(curl -fsS -X POST "$BRIDGE/pair" -H "Content-Type: application/json" -d "{\"code\":\"$CODE\"}")
  export AGENT_WATCH_TOKEN=$(python3 -c "import json,sys; print(json.load(sys.stdin)['token'])" <<< "$RESP")
fi

curl -fsS -X POST "$BRIDGE/command" \
  -H "Authorization: Bearer $AGENT_WATCH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"spawnProfile\":\"$PROFILE\"}" | python3 -m json.tool