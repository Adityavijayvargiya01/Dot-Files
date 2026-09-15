// Traffic Herdr: report OpenCode agent state to the shared status files.
// Lives in the Omarchy plugin; symlink into ~/.config/opencode/plugins/.

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const SOURCE = "aditya.herdr";
const harness = "opencode";
const agentId = `opencode-${process.pid}`;
const pluginDir = join(
  process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
  "omarchy/plugins/aditya.herdr",
);
const reporter = join(pluginDir, "report-status");

const SESSION_STATE_BY_STATUS = new Map([
  ["idle", "idle"],
  ["active", "working"],
  ["busy", "working"],
  ["pending", "working"],
  ["retry", "working"],
  ["running", "working"],
  ["streaming", "working"],
  ["working", "working"],
]);

const CHILD_EVENT_STATES = new Map([
  ["permission.asked", "blocked"],
  ["question.asked", "blocked"],
  ["permission.replied", "working"],
  ["question.replied", "working"],
  ["question.rejected", "working"],
]);

function run(args) {
  try {
    const child = spawn(reporter, args, { stdio: "ignore", detached: true });
    child.unref();
  } catch {
    // Status is best-effort; never break the session.
  }
}

function report(state) {
  run(["set", harness, agentId, state, String(process.pid)]);
}

function clear() {
  run(["clear", agentId]);
}

function stateFromSessionStatus(status) {
  const kind = typeof status === "string" ? status : status?.type;
  return typeof kind === "string" ? SESSION_STATE_BY_STATUS.get(kind.toLowerCase()) : undefined;
}

function sessionIDFromProperties(properties) {
  return typeof properties?.sessionID === "string" && properties.sessionID
    ? properties.sessionID
    : undefined;
}

export const TrafficHerdrPlugin = async () => {
  const sessions = new Map();
  const childSessions = new Map();
  let lastState;

  function worstState() {
    const states = [...sessions.values()];
    if (states.includes("blocked")) return "blocked";
    if (states.includes("working")) return "working";
    return "idle";
  }

  function publish(force = false) {
    const next = sessions.size ? worstState() : "idle";
    if (!force && next === lastState) return;
    lastState = next;
    report(next);
  }

  function setState(sessionID, state) {
    if (sessionID) sessions.set(sessionID, state);
    else sessions.set("default", state);
    publish();
  }

  function rootOf(sessionID) {
    let current = sessionID;
    const seen = new Set();
    while (current && childSessions.has(current) && !seen.has(current)) {
      seen.add(current);
      current = childSessions.get(current);
    }
    return current || sessionID;
  }

  report("idle");

  return {
    "chat.message": async ({ sessionID }) => {
      if (sessionID && childSessions.has(sessionID)) return;
      setState(sessionID, "working");
    },
    event: async ({ event }) => {
      const type = event?.type;
      const properties = event?.properties ?? {};
      const sessionID = sessionIDFromProperties(properties);
      const info = properties.info;
      if (info?.id && info.parentID) {
        childSessions.set(info.id, info.parentID);
      }
      if (sessionID && childSessions.has(sessionID)) {
        const state = CHILD_EVENT_STATES.get(type);
        if (state) setState(rootOf(sessionID), state);
        return;
      }

      switch (type) {
        case "session.status": {
          const state = stateFromSessionStatus(properties.status);
          if (state) setState(sessionID, state);
          break;
        }
        case "tool.execute.before":
        case "tool.execute.after":
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          setState(sessionID, "working");
          break;
        case "permission.asked":
        case "question.asked":
        case "session.error":
          setState(sessionID, "blocked");
          break;
        case "session.idle":
          setState(sessionID, "idle");
          break;
        case "session.deleted":
          if (sessionID) sessions.delete(sessionID);
          publish(true);
          break;
        default:
          break;
      }
    },
    dispose: async () => {
      clear();
    },
  };
};

export default {
  id: `${SOURCE}.opencode`,
  server: TrafficHerdrPlugin,
};
