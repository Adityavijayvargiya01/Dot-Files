// Traffic: report omp agent state to the shared status files.
// Lives in the Omarchy plugin; symlink into ~/.omp/agent/extensions/.
// State machine matches Herdr's omp integration (working / blocked / idle).

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

type AgentState = "working" | "blocked" | "idle";

type ExtensionApi = {
  on: (event: string, handler: (event: unknown, ctx: unknown) => void) => void;
  events?: {
    on?: (event: string, handler: (data: unknown) => void) => void;
  };
  getSessionName?: () => string | undefined;
};

const harness = "omp";
const agentId = `omp-${process.pid}`;
const pluginDir = join(
  process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
  "omarchy/plugins/aditya.traffic",
);
const reporter = join(pluginDir, "report-status");
let currentSessionName: string | undefined;
const idleDebounceMs = 250;
const retryGraceMs = 2500;
const retryableErrorPattern =
  /overloaded|provider.?returned.?error|rate.?limit|too many requests|429|500|502|503|504|service.?unavailable|server.?error|internal.?error|network.?error|connection.?error|connection.?refused|connection.?lost|websocket.?closed|websocket.?error|other side closed|fetch failed|upstream.?connect|reset before headers|socket hang up|ended without|http2 request did not get a response|timed? out|timeout|terminated|retry delay/i;

function field(value: unknown, key: string): unknown {
  if (typeof value !== "object" || value === null) return undefined;
  return (value as Record<string, unknown>)[key];
}

function shouldReport(ctx: unknown): boolean {
  const mode = field(ctx, "mode");
  if (mode === "print" || mode === "json") return false;
  if (mode === "tui" || mode === "rpc") return true;
  return field(ctx, "hasUI") === true;
}

function retryableError(event: unknown): boolean {
  const messages = field(event, "messages");
  if (!Array.isArray(messages)) return false;
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const message = messages[i];
    if (field(message, "role") !== "assistant") continue;
    if (field(message, "stopReason") !== "error") return false;
    const errorMessage = field(message, "errorMessage");
    return retryableErrorPattern.test(typeof errorMessage === "string" ? errorMessage : "");
  }
  return false;
}

function run(args: string[]): void {
  try {
    const child = spawn(reporter, args, { stdio: "ignore", detached: true });
    child.unref();
  } catch {
    // Status is best-effort; never break the session.
  }
}

function report(state: AgentState): void {
  const args = ["set", harness, agentId, state, String(process.pid)];
  if (currentSessionName) args.push(currentSessionName);
  run(args);
}

function clear(): void {
  run(["clear", agentId]);
}

export default function (pi: ExtensionApi): void {
  let rootSession = false;
  let published = false;
  let agentActive = false;
  let retryHoldActive = false;
  let failureBlocked = false;
  let blockedCount = 0;
  let lastState: AgentState | undefined;
  let lastLabel: string | undefined;
  let idleTimer: NodeJS.Timeout | undefined;
  let retryTimer: NodeJS.Timeout | undefined;
  let nameTimer: NodeJS.Timeout | undefined;

  function syncSessionName(ctx?: unknown): void {
    let name: unknown;
    try {
      const manager = field(ctx, "sessionManager") as
        | { getSessionName?: () => unknown }
        | undefined;
      name = manager?.getSessionName?.();
    } catch {
      name = undefined;
    }
    if (typeof name !== "string" || !name.trim()) {
      try {
        name = pi.getSessionName?.();
      } catch {
        name = undefined;
      }
    }
    currentSessionName =
      typeof name === "string" && name.trim()
        ? name.trim().replace(/\s+/g, " ")
        : undefined;
  }

  function clearPendingTimers(): void {
    clearTimeout(idleTimer);
    clearTimeout(retryTimer);
    idleTimer = undefined;
    retryTimer = undefined;
  }

  function clearFailureState(): void {
    retryHoldActive = false;
    failureBlocked = false;
  }

  function desired(): AgentState {
    if (blockedCount > 0 || failureBlocked) return "blocked";
    if (agentActive || retryHoldActive) return "working";
    return "idle";
  }

  function publish(force = false): void {
    const next = desired();
    if (!force && next === lastState && currentSessionName === lastLabel) return;
    lastState = next;
    lastLabel = currentSessionName;
    published = true;
    report(next);
  }

  function scheduleIdle(): void {
    clearPendingTimers();
    clearFailureState();
    idleTimer = setTimeout(() => {
      idleTimer = undefined;
      publish();
    }, idleDebounceMs);
    idleTimer.unref?.();
  }

  function holdForRetry(): void {
    clearPendingTimers();
    retryHoldActive = true;
    failureBlocked = false;
    publish();
    retryTimer = setTimeout(() => {
      retryTimer = undefined;
      retryHoldActive = false;
      failureBlocked = true;
      publish();
    }, retryGraceMs);
    retryTimer.unref?.();
  }

  function startNameWatcher(): void {
    if (nameTimer) return;
    nameTimer = setInterval(() => {
      if (!rootSession) return;
      const previous = currentSessionName;
      syncSessionName();
      if (currentSessionName !== previous) publish();
    }, 2000);
    nameTimer.unref?.();
  }

  function activateRoot(ctx: unknown): boolean {
    if (!shouldReport(ctx)) return false;
    syncSessionName(ctx);
    rootSession = true;
    startNameWatcher();
    return true;
  }

  function activateBlocked(): void {
    clearPendingTimers();
    blockedCount += 1;
    publish();
  }

  function deactivateBlocked(): void {
    blockedCount = Math.max(0, blockedCount - 1);
    publish();
  }

  pi.events?.on?.("herdr:blocked", (data: unknown) => {
    if (!rootSession) return;
    if (field(data, "active") !== true) {
      deactivateBlocked();
      return;
    }
    activateBlocked();
  });

  pi.on("session_start", (_event: unknown, ctx: unknown) => {
    if (!activateRoot(ctx)) return;
    const isIdle = field(ctx, "isIdle");
    agentActive = typeof isIdle === "function" && isIdle() === false;
    publish(true);
  });

  pi.on("session_switch", (_event: unknown, ctx: unknown) => {
    if (!activateRoot(ctx)) return;
    clearPendingTimers();
    clearFailureState();
    agentActive = false;
    blockedCount = 0;
    publish(true);
  });

  pi.on("agent_start", (_event: unknown, ctx: unknown) => {
    if (!rootSession) {
      if (!activateRoot(ctx)) return;
    } else {
      syncSessionName(ctx);
    }
    clearPendingTimers();
    clearFailureState();
    agentActive = true;
    publish();
  });

  pi.on("tool_approval_requested", (_event: unknown, ctx: unknown) => {
    if (!rootSession && !activateRoot(ctx)) return;
    activateBlocked();
  });

  pi.on("tool_approval_resolved", (_event: unknown, ctx: unknown) => {
    if (!rootSession && !activateRoot(ctx)) return;
    deactivateBlocked();
  });

  pi.on("tool_execution_start", (event: unknown, ctx: unknown) => {
    if (field(event, "toolName") !== "ask") return;
    if (!rootSession && !activateRoot(ctx)) return;
    activateBlocked();
  });

  pi.on("tool_execution_end", (event: unknown, ctx: unknown) => {
    if (field(event, "toolName") !== "ask") return;
    if (!rootSession && !activateRoot(ctx)) return;
    deactivateBlocked();
  });

  pi.on("agent_end", (event: unknown, ctx: unknown) => {
    if (!rootSession || !agentActive) return;
    syncSessionName(ctx);
    if (field(event, "willContinue") === true) return;
    agentActive = false;
    if (retryableError(event)) {
      holdForRetry();
      return;
    }
    scheduleIdle();
  });

  const refreshSessionName = (_event: unknown, ctx: unknown): void => {
    if (!rootSession) return;
    syncSessionName(ctx);
    publish();
  };
  pi.on("session_info_changed", refreshSessionName);
  pi.on("session_info_update", refreshSessionName);

  pi.on("session_shutdown", () => {
    clearPendingTimers();
    clearInterval(nameTimer);
    nameTimer = undefined;
    if (!published) return;
    published = false;
    rootSession = false;
    lastState = undefined;
    lastLabel = undefined;
    currentSessionName = undefined;
    clear();
  });
}
