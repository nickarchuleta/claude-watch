import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execSync } from "node:child_process";

function findBinary(name, candidates = []) {
  for (const c of candidates) {
    try {
      fs.accessSync(c, fs.constants.X_OK);
      return c;
    } catch { /* continue */ }
  }
  try {
    return execSync(`which ${name} 2>/dev/null`, { encoding: "utf-8" }).trim() || null;
  } catch {
    return null;
  }
}

function expandHome(p) {
  if (!p || typeof p !== "string") return p;
  return p.replace(/^~(?=$|[/\\])/, os.homedir());
}

function readPiDefaults() {
  const settingsPath = path.join(os.homedir(), ".pi", "agent", "settings.json");
  try {
    const settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    return {
      provider: settings.defaultProvider || process.env.AGENT_WATCH_PI_PROVIDER || "openrouter",
      model: settings.defaultModel || process.env.AGENT_WATCH_PI_MODEL || "openrouter/free",
      thinking: settings.defaultThinkingLevel || process.env.AGENT_WATCH_PI_THINKING || "high",
    };
  } catch {
    return {
      provider: process.env.AGENT_WATCH_PI_PROVIDER || "openrouter",
      model: process.env.AGENT_WATCH_PI_MODEL || "openrouter/free",
      thinking: process.env.AGENT_WATCH_PI_THINKING || "high",
    };
  }
}

const BUILTIN_AGENTS = () => {
  const piDefaults = readPiDefaults();
  return {
    claude: {
      id: "claude",
      label: "Claude Code",
      binary: findBinary("claude", [
        `${os.homedir()}/.local/bin/claude`,
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
      ]),
      spawnArgs: () => [],
      resumeArgs: () => [],
      execMode: "claude",
      monitor: "hooks",
    },
    codex: {
      id: "codex",
      label: "Codex",
      binary: findBinary("codex", [
        `${os.homedir()}/.local/bin/codex`,
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
      ]),
      spawnArgs: () => [],
      resumeArgs: () => ["resume", "{sessionId}", "--no-alt-screen"],
      execMode: "codex",
      monitor: "codex",
    },
    pi: {
      id: "pi",
      label: `Pi (${piDefaults.provider}/${piDefaults.model})`,
      binary: findBinary("pi", [
        `${os.homedir()}/.npm-global/bin/pi`,
        `${os.homedir()}/.local/bin/pi`,
        "/opt/homebrew/bin/pi",
      ]),
      spawnArgs: () => [
        "--provider", piDefaults.provider,
        "--model", piDefaults.model,
      ],
      resumeArgs: () => [
        "--resume",
        "--provider", piDefaults.provider,
        "--model", piDefaults.model,
      ],
      execMode: "pi",
      monitor: "pi",
      sessionRoot: path.join(os.homedir(), ".pi", "agent", "sessions"),
    },
  };
};

function loadUserConfig() {
  const candidates = [
    process.env.AGENT_WATCH_AGENTS_FILE,
    path.join(os.homedir(), ".agent-watch", "agents.json"),
    path.join(process.cwd(), "skill", "agents.json"),
  ].filter(Boolean);

  for (const file of candidates) {
    try {
      const raw = fs.readFileSync(expandHome(file), "utf-8");
      return JSON.parse(raw);
    } catch { /* try next */ }
  }
  return null;
}

function mergeCustomAgents(registry, userConfig) {
  if (!userConfig?.agents) return registry;
  for (const [id, spec] of Object.entries(userConfig.agents)) {
    const bin = spec.binary
      ? (path.isAbsolute(expandHome(spec.binary))
        ? expandHome(spec.binary)
        : findBinary(spec.binary, [expandHome(spec.binary)]))
      : findBinary(id, []);
    registry[id] = {
      id,
      label: spec.label || id,
      binary: bin,
      spawnArgs: () => spec.spawnArgs || [],
      resumeArgs: () => spec.resumeArgs || [],
      execMode: spec.execMode || "generic",
      execArgs: spec.execArgs || ["-p"],
      monitor: spec.monitor || null,
      sessionRoot: spec.sessionRoot ? expandHome(spec.sessionRoot) : null,
    };
  }
  return registry;
}

let _cache = null;

export function getAgentRegistry(force = false) {
  if (_cache && !force) return _cache;
  const registry = mergeCustomAgents(BUILTIN_AGENTS(), loadUserConfig());
  _cache = {
    agents: registry,
    profiles: loadUserConfig()?.profiles || DEFAULT_PROFILES,
  };
  return _cache;
}

export const DEFAULT_PROFILES = {
  money: {
    label: "Money Printer",
    agent: "pi",
    cwd: expandHome(process.env.AGENT_WATCH_MONEY_CWD || "~/my-pi-projects"),
    description: "Trading agents, backtests, financial command center",
  },
  life: {
    label: "Life Ops",
    agent: "claude",
    cwd: expandHome(process.env.AGENT_WATCH_LIFE_CWD || "~/Documents/Obsidian Vault"),
    description: "Flights, hotels, bills, calendar, biz ops",
  },
};

export function availableAgentsList() {
  const { agents } = getAgentRegistry();
  return Object.values(agents)
    .filter((a) => a.binary)
    .map((a) => a.id);
}

export function getAgent(agentId) {
  const { agents } = getAgentRegistry();
  return agents[agentId] || null;
}

export function getProfile(profileId) {
  const { profiles } = getAgentRegistry();
  return profiles[profileId] || null;
}

export function listProfiles() {
  const { profiles } = getAgentRegistry();
  return Object.entries(profiles).map(([id, p]) => ({ id, ...p }));
}

export function buildSpawnArgs(agentId, { sessionId } = {}) {
  const agent = getAgent(agentId);
  if (!agent?.binary) return null;
  const args = [...(agent.spawnArgs?.() || [])];
  return { binary: agent.binary, args };
}

export function buildResumeArgs(agentId, sessionId) {
  const agent = getAgent(agentId);
  if (!agent?.binary) return null;
  const template = agent.resumeArgs?.() || [];
  const args = template.map((a) => (a === "{sessionId}" ? sessionId : a));
  return { binary: agent.binary, args };
}

export function buildExecCommand(agentId, promptText) {
  const agent = getAgent(agentId);
  if (!agent?.binary) return null;
  const mode = agent.execMode || "generic";

  if (mode === "claude") {
    return { binary: agent.binary, args: ["-p", promptText, "--continue"] };
  }
  if (mode === "codex") {
    return { binary: agent.binary, args: ["exec", promptText] };
  }
  if (mode === "pi") {
    const spawn = buildSpawnArgs(agentId);
    return {
      binary: agent.binary,
      args: [...(spawn?.args || []), "-p", promptText],
    };
  }

  const execArgs = agent.execArgs || ["-p"];
  return { binary: agent.binary, args: [...execArgs, promptText] };
}

export function agentBinary(agentId) {
  return getAgent(agentId)?.binary || null;
}