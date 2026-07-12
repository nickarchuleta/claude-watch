# Remote Access — No Same WiFi Required

Upstream Agent Watch requires the watch, iPhone, and Mac on the same LAN. This fork adds two paths that work anywhere.

## Recommended: iPhone relay + Tailscale

**Works when:** iPhone is on cellular or any WiFi; watch only needs Bluetooth to iPhone.

```
Apple Watch  --WCSession-->  iPhone  --Tailscale/cellular-->  Mac bridge
```

### Mac

```bash
cd skill
./start-remote.sh tailscale   # or: local + manual tailscale serve
```

Bridge banner shows `Tailscale IP` and `Remote URL` (e.g. `https://your-mac.tail12345.ts.net`).

### iPhone

1. Install [Tailscale](https://tailscale.com/download) and sign in (same tailnet as Mac).
2. Open Agent Watch → **Remote (Tailscale / tunnel URL)**.
3. Enter the Remote URL from the bridge banner (no port needed if using Tailscale Serve on 443).
4. Enter the 6-digit pairing code.

### Apple Watch

1. Open Agent Watch → **Connect via iPhone** (default).
2. No Mac IP, no pairing code on the watch.
3. Terminal + permissions flow through the paired iPhone.

## Alternative: Cloudflare quick tunnel

**Works when:** You need a URL without Tailscale. URL rotates each run.

```bash
cd skill
./start-remote.sh cloudflare
```

Copy the `*.trycloudflare.com` URL into iPhone pairing (Remote URL). Watch still uses **Connect via iPhone**.

Security: pairing code + bearer token required; tunnel is public — use only for testing.

## LAN mode (unchanged)

Same WiFi still works:

- iPhone: auto Bonjour or manual `192.168.x.x`
- Watch: **Direct to Mac (LAN)** in onboarding

## Why same WiFi was required

| Component | Old behavior | This fork |
|-----------|--------------|-----------|
| iPhone → Mac | Bonjour (LAN only) | + Remote URL (Tailscale, tunnel, 100.x IP) |
| Watch → Mac | Direct HTTP/SSE to LAN IP | **Via iPhone** relay (WCSession) |
| Watch → Mac (optional) | LAN only | Direct LAN / Tailscale host on watch |

The watch app previously ignored iPhone relay messages and always talked to the Mac directly — that is why the watch needed same WiFi even though the architecture diagram showed iPhone in the middle.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| iPhone can't reach Mac remotely | Confirm Tailscale on both; run `tailscale status`; use HTTPS URL from banner |
| Watch stuck on "Waiting for iPhone" | Pair iPhone to Mac first; keep iPhone app open once |
| Permissions work on iPhone but not watch | Watch must use **Connect via iPhone**, not Direct LAN |
| SSE drops on cellular | Normal — iPhone RelayService reconnects; watch gets batched terminal updates |

## Fork

https://github.com/nickarchuleta/claude-watch