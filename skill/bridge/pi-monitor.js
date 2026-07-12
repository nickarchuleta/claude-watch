import fs from "node:fs";
import path from "node:path";
import { getAgent } from "./agents.js";

const PI_SCAN_INTERVAL_MS = 1500;
const PI_SCAN_LIMIT = 25;
const PI_BOOTSTRAP_LOOKBACK_MS = 30 * 60 * 1000;

function safeStat(p) {
  try { return fs.statSync(p); } catch { return null; }
}

function readSlice(filePath, start, length) {
  const fd = fs.openSync(filePath, "r");
  try {
    const buf = Buffer.alloc(length);
    const n = fs.readSync(fd, buf, 0, length, start);
    return buf.subarray(0, n).toString("utf-8");
  } finally {
    fs.closeSync(fd);
  }
}

function listRecentPiSessions(rootDir) {
  const out = [];
  const stack = [rootDir];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) { stack.push(full); continue; }
      if (!e.isFile() || !e.name.endsWith(".jsonl")) continue;
      const st = safeStat(full);
      if (st) out.push({ filePath: full, mtimeMs: st.mtimeMs, size: st.size });
    }
  }
  out.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return out.slice(0, PI_SCAN_LIMIT);
}

function toolContentText(content) {
  if (!Array.isArray(content)) return "";
  return content
    .filter((c) => c?.type === "text")
    .map((c) => c.text)
    .join("\n")
    .slice(0, 2000);
}

export function createPiMonitor({ log, pushSseEvent, touchExternalSession, endExternalSession }) {
  const agent = getAgent("pi");
  const root = agent?.sessionRoot;
  if (!root || !fs.existsSync(root)) {
    log("info", "Pi monitor disabled — no session root");
    return { start: () => {}, stop: () => {} };
  }

  const files = new Map();
  let timer = null;

  function handleLine(line, state, { bootstrap = false } = {}) {
    let parsed;
    try { parsed = JSON.parse(line); } catch { return; }

    if (parsed.type === "session" && parsed.id) {
      state.sessionId = parsed.id;
      state.cwd = parsed.cwd || state.cwd;
      state.createdAt = Date.parse(parsed.timestamp || "") || Date.now();
      if (bootstrap) return;
      touchExternalSession(parsed.id, state.cwd, state.createdAt, "pi");
      return;
    }

    if (!state.sessionId || bootstrap) return;

    if (parsed.type === "message" && parsed.message) {
      const msg = parsed.message;
      const sid = state.sessionId;

      if (msg.role === "assistant" && Array.isArray(msg.content)) {
        for (const block of msg.content) {
          if (block.type === "toolCall") {
            const name = block.name || "tool";
            const args = block.arguments || {};
            const toolInput = name === "bash"
              ? { command: args.command || args.cmd || "" }
              : name === "read" || name === "write" || name === "edit"
                ? { file_path: args.path || args.file_path || args.file || "" }
                : args;
            pushSseEvent("tool-output", {
              source: "pi",
              tool_name: name.charAt(0).toUpperCase() + name.slice(1),
              tool_input: toolInput,
              tool_output: null,
            }, sid);
          }
          if (block.type === "text" && block.text?.trim()) {
            pushSseEvent("tool-output", {
              source: "pi",
              tool_name: "PiMessage",
              tool_input: {},
              tool_output: block.text.slice(0, 500),
            }, sid);
          }
        }
      }

      if (msg.role === "toolResult") {
        const output = toolContentText(msg.content);
        if (output) {
          pushSseEvent("tool-output", {
            source: "pi",
            tool_name: msg.toolName || "tool",
            tool_input: {},
            tool_output: output,
          }, sid);
        }
      }

      if (msg.stopReason === "error" && msg.errorMessage) {
        pushSseEvent("error", { error: `[pi] ${msg.errorMessage}`, source: "pi" }, sid);
      }
    }
  }

  function scan() {
    const recent = listRecentPiSessions(root);
    const active = new Set(recent.map((f) => f.filePath));

    for (const f of recent) {
      const stat = safeStat(f.filePath);
      if (!stat) continue;

      let state = files.get(f.filePath);
      if (!state) {
        state = { offset: 0, remainder: "", sessionId: null, cwd: null, createdAt: null, initialized: false };
        files.set(f.filePath, state);
      }

      if (!state.initialized) {
        const header = stat.size > 0 ? readSlice(f.filePath, 0, Math.min(stat.size, 65536)) : "";
        const allowBootstrap = Date.now() - stat.mtimeMs <= PI_BOOTSTRAP_LOOKBACK_MS;
        for (const line of header.split("\n")) {
          if (!line.trim()) continue;
          handleLine(line, state, { bootstrap: true });
          if (state.sessionId && allowBootstrap) {
            touchExternalSession(state.sessionId, state.cwd, state.createdAt, "pi");
          }
          if (state.sessionId) break;
        }
        state.offset = stat.size;
        state.initialized = true;
        continue;
      }

      if (stat.size < state.offset) {
        state.offset = 0;
        state.remainder = "";
      }
      if (stat.size === state.offset) continue;

      const chunk = readSlice(f.filePath, state.offset, stat.size - state.offset);
      state.offset = stat.size;
      const text = state.remainder + chunk;
      const lines = text.split("\n");
      state.remainder = lines.pop() || "";
      for (const line of lines) {
        if (!line.trim()) continue;
        handleLine(line, state);
      }
    }

    for (const [filePath, state] of files) {
      if (!active.has(filePath) && state.sessionId) {
        endExternalSession(state.sessionId, "pi-idle");
        files.delete(filePath);
      }
    }
  }

  return {
    start() {
      if (timer) return;
      log("info", `Pi session monitor watching ${root}`);
      timer = setInterval(scan, PI_SCAN_INTERVAL_MS);
      scan();
    },
    stop() {
      if (timer) clearInterval(timer);
      timer = null;
    },
  };
}