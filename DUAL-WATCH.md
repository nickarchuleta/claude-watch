# Dual-Watch Command Center — Nick's Setup

Two cellular Apple Watches as dumb-phone command wrists. Each watch relays through its paired iPhone to one Mac bridge. No same-WiFi requirement (see [REMOTE.md](REMOTE.md)).

## Wrist roles

| Wrist | Profile | Agent | Default cwd | Job |
|-------|---------|-------|-------------|-----|
| **Left / Finance** | `money` | **Pi** (`openrouter/free` or your pinned model) | `~/my-pi-projects` | Trading agents, backtests, money printer — token waterfalls during backtest |
| **Right / Life** | `life` | **Claude Code** | `~/Documents/Obsidian Vault` | Flights, hotels, bills, appointments, calendar, biz ops |

Edit paths in `skill/agents.json` or env:

```bash
export AGENT_WATCH_MONEY_CWD=~/trading
export AGENT_WATCH_LIFE_CWD=~/Documents/Obsidian\ Vault
export AGENT_WATCH_PI_MODEL=openrouter/free
export AGENT_WATCH_PI_PROVIDER=openrouter
```

Pi reads `~/.pi/agent/settings.json` when env is unset (Nick's machine already has `defaultModel: openrouter/free`).

## Mac (one bridge, many sessions)

```bash
cd claude-watch/skill
./setup-hooks.sh          # Claude → bridge hooks
./start-remote.sh tailscale   # optional: iPhone on cellular
cd bridge && npm install
node server.js
```

Bridge monitors:

- **Claude** — HTTP hooks (`PostToolUse`, `PermissionRequest`, …)
- **Codex** — session JSONL + TUI log (if you use Codex)
- **Pi** — `~/.pi/agent/sessions/**/*.jsonl` (tool calls + messages)

## Spawn from iPhone or curl

```bash
# Money wrist session (Pi + OpenRouter)
curl -s -X POST http://127.0.0.1:7860/command \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"spawnProfile":"money"}'

# Life wrist session (Claude on vault)
curl -s -X POST http://127.0.0.1:7860/command \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"spawnProfile":"life"}'

# Raw agent spawn
curl -s -X POST ... -d '{"spawn":"pi","cwd":"~/my-pi-projects"}'
```

Swift API: `bridgeClient.spawnProfile("money")`

## Per-watch iPhone pairing

Use **two iPhones** (or one phone per watch if watches have their own lines):

1. Each iPhone installs Agent Watch + Tailscale
2. Each pairs to the **same** Mac bridge (or two Macs if you split later)
3. Each **Watch** → **Connect via iPhone** (no LAN)

Watch A only needs the finance iPhone relay. Watch B only needs the life iPhone relay. Permissions and terminal lines batch over WCSession.

## Pi without Claude hooks

Pi has no HTTP hooks like Claude. The bridge **tails Pi session files** instead. Run Pi normally in a terminal:

```bash
cd ~/my-pi-projects
pi --provider openrouter --model openrouter/free
```

Or spawn from the bridge/iPhone. Tool output appears on the watch within ~1.5s.

**Note:** Pi permission prompts are TUI on Mac — approve on Mac or via iPhone if Claude-style hooks are added later. For backtest waterfalls, you mostly need **read-only terminal stream + occasional voice inject**, not per-tool approve on watch.

## Custom CLIs

Drop extra agents in `~/.agent-watch/agents.json`:

```json
{
  "agents": {
    "opencode": {
      "binary": "opencode",
      "label": "OpenCode",
      "spawnArgs": [],
      "execArgs": ["-p"],
      "execMode": "generic",
      "monitor": null
    }
  }
}
```

Restart bridge. Agent shows in `/status` → `availableAgents`.

## Fork

https://github.com/nickarchuleta/claude-watch