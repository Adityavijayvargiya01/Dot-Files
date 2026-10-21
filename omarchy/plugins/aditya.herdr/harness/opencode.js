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
  ["form.created", "blocked"],
  ["permission.replied", "working"],
  ["question.replied", "working"],
  ["question.rejected", "working"],
  ["form.replied", "working"],
  ["form.cancelled", "working"],
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

function sessionIDFromV2Event(event) {
  const data = event?.data;
  if (typeof data?.sessionID === "string" && data.sessionID) {
    return data.sessionID;
  }
  if (typeof data?.form?.sessionID === "string" && data.form.sessionID) {
    return data.form.sessionID;
  }
  return undefined;
}

export async function TrafficHerdrSetup(ctx) {
  const sessions = new Map();
  const titles = new Map();
  const childSessions = new Map();
  const fetchingTitles = new Set();
  const pid = String(process.pid);
  const legacyId = `${harness}-${process.pid}`;
  const recentWindowMs = 12 * 60 * 60 * 1000;
  let disposed = false;

  function sessionAgentId(sessionID) {
    return `${harness}-${sessionID}`;
  }

  function labelFor(sessionID) {
    return titles.get(sessionID) || harness;
  }

  function reportSession(sessionID, state) {
    if (disposed || !sessionID) return;
    run([
      "set",
      harness,
      sessionAgentId(sessionID),
      state,
      pid,
      labelFor(sessionID),
    ]);
  }

  function clearSession(sessionID) {
    if (!sessionID) return;
    run(["clear", sessionAgentId(sessionID)]);
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

  function rememberTitle(sessionID, title) {
    if (!sessionID || typeof title !== "string" || !title.trim()) return;
    const rootID = rootOf(sessionID);
    titles.set(rootID, title.split(/\s+/).join(" ").trim());
    const state = sessions.get(rootID);
    if (state) reportSession(rootID, state);
  }

  function fetchTitle(sessionID) {
    if (!sessionID || titles.has(sessionID) || fetchingTitles.has(sessionID)) return;
    fetchingTitles.add(sessionID);
    void (async () => {
      try {
        const result = await ctx.session.get({ sessionID });
        const session = result?.data ?? result;
        if (session?.title) rememberTitle(sessionID, session.title);
      } catch {
        // Title is cosmetic; status still works without it.
      } finally {
        fetchingTitles.delete(sessionID);
      }
    })();
  }

  function setState(sessionID, state) {
    if (!sessionID) return;
    const rootID = rootOf(sessionID);
    const previous = sessions.get(rootID);
    sessions.set(rootID, state);
    fetchTitle(rootID);
    if (previous !== state) reportSession(rootID, state);
  }

  async function handleV2Event(event) {
    const type = event?.type;
    const data = event?.data ?? {};
    const sessionID = sessionIDFromV2Event(event);
    const info = data.info ?? data.session;
    const infoID =
      typeof data.sessionID === "string" && data.sessionID
        ? data.sessionID
        : typeof data.id === "string" && data.id
          ? data.id
          : typeof info?.id === "string"
            ? info.id
            : undefined;
    const parentID =
      typeof data.parentID === "string" && data.parentID
        ? data.parentID
        : typeof info?.parentID === "string" && info.parentID
          ? info.parentID
          : undefined;
    if (infoID && parentID) childSessions.set(infoID, parentID);

    const titledID =
      typeof data.sessionID === "string" && data.sessionID
        ? data.sessionID
        : typeof data.id === "string" && data.id
          ? data.id
          : infoID;
    const title =
      typeof data.title === "string" && data.title
        ? data.title
        : typeof info?.title === "string" && info.title
          ? info.title
          : undefined;
    if (titledID && title) rememberTitle(titledID, title);

    if (sessionID && childSessions.has(sessionID)) {
      const state = CHILD_EVENT_STATES.get(type);
      if (state) setState(rootOf(sessionID), state);
      return;
    }

    switch (type) {
      case "session.status": {
        const state = stateFromSessionStatus(data.status);
        if (state) setState(sessionID, state);
        break;
      }
      case "session.inbox.delivered":
      case "session.inbox.enqueued":
      case "session.execution.started":
      case "session.step.started":
      case "session.text.started":
      case "session.tool.called":
      case "session.tool.progress":
      case "session.tool.success":
      case "session.tool.failed":
      case "session.compaction.started":
      case "session.compaction.ended":
      case "permission.replied":
      case "form.replied":
      case "form.cancelled":
        setState(sessionID, "working");
        break;
      case "permission.asked":
      case "form.created":
      case "session.execution.failed":
      case "session.compaction.failed":
      case "session.step.failed":
        setState(sessionID, "blocked");
        break;
      case "session.execution.interrupted":
      case "session.execution.succeeded":
      case "session.idle":
        setState(sessionID, "idle");
        break;
      case "session.deleted": {
        const deletedID = sessionID || infoID;
        if (!deletedID) break;
        const rootID = rootOf(deletedID);
        if (rootID === deletedID) {
          sessions.delete(deletedID);
          titles.delete(deletedID);
          clearSession(deletedID);
        } else {
          childSessions.delete(deletedID);
        }
        break;
      }
      default:
        break;
    }
  }

  async function seedRecentSessions() {
    try {
      const query = { limit: 100 };
      if (ctx.location?.directory) query.directory = ctx.location.directory;
      const page = await ctx.session.list(query);
      const list = Array.isArray(page)
        ? page
        : Array.isArray(page?.data)
          ? page.data
          : [];
      const now = Date.now();
      for (const session of list) {
        if (!session?.id || session.parentID) continue;
        const stamp = session.time?.viewed ?? session.time?.updated ?? 0;
        if (!stamp || now - stamp > recentWindowMs) continue;
        if (session.title)
          titles.set(session.id, session.title.split(/\s+/).join(" ").trim());
        if (sessions.has(session.id)) continue;
        sessions.set(session.id, "idle");
        reportSession(session.id, "idle");
      }
    } catch {
      // Seeding is optional; live events still drive status.
    }
  }

  run(["clear", legacyId]);

  const controller = new AbortController();
  void (async () => {
    try {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        try {
          await handleV2Event(event);
        } catch {
          // Status is best-effort; never break the session.
        }
      }
    } catch {
      // Subscription ended (e.g. unload); nothing to report.
    }
  })();

  await ctx.session.hook("prompt", async (event) => {
    if (event.sessionID && childSessions.has(event.sessionID)) return;
    setState(event.sessionID, "working");
  });

  await seedRecentSessions();

  return () => {
    disposed = true;
    controller.abort();
    for (const sessionID of sessions.keys()) clearSession(sessionID);
    run(["clear", legacyId]);
  };
}


export default {
  id: `${SOURCE}.opencode`,
  setup: TrafficHerdrSetup,
  server: TrafficHerdrPlugin,
};
