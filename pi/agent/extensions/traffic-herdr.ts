// Traffic: report pi agent state to the shared status files.
// Lives in the Omarchy plugin; symlink into ~/.pi/agent/extensions/.

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

type AgentState = "working" | "blocked" | "idle";

const harness = "pi";
const agentId = `pi-${process.pid}`;
const pluginDir = join(
  process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
  "omarchy/plugins/aditya.traffic",
);
const reporter = join(pluginDir, "report-status");
let currentSessionName: string | undefined;

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

export default function (pi: any) {
  let rootSession = false;
  let agentActive = false;
  let promptCount = 0;
  let lastState: AgentState | undefined;
  let lastLabel: string | undefined;

  function syncSessionName(ctx?: any): void {
    let name: unknown;
    try {
      name = ctx?.sessionManager?.getSessionName?.();
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

  function desired(): AgentState {
    if (promptCount > 0) return "blocked";
    if (agentActive) return "working";
    return "idle";
  }

  function publish(force = false): void {
    const next = desired();
    if (!force && next === lastState && currentSessionName === lastLabel) return;
    lastState = next;
    lastLabel = currentSessionName;
    report(next);
  }

  pi.on("session_start", async (_event: any, ctx: any) => {
    if (ctx?.mode !== "tui") return;
    rootSession = true;
    syncSessionName(ctx);
    agentActive = ctx?.isIdle?.() === false;
    promptCount = 0;
    publish(true);
  });

  pi.on("session_info_changed", (_event: any, ctx: any) => {
    if (!rootSession) return;
    syncSessionName(ctx);
    publish();
  });

  pi.on("agent_start", (_event: any, ctx: any) => {
    if (!rootSession) return;
    syncSessionName(ctx);
    agentActive = true;
    publish();
  });

  pi.on("agent_settled", (_event: any, ctx: any) => {
    if (!rootSession) return;
    syncSessionName(ctx);
    if (ctx?.isIdle?.() === true) agentActive = false;
    publish();
  });

  pi.on("ui_prompt_start", () => {
    if (!rootSession) return;
    promptCount += 1;
    publish();
  });

  pi.on("ui_prompt_end", () => {
    if (!rootSession) return;
    promptCount = Math.max(0, promptCount - 1);
    publish();
  });

  pi.on("session_shutdown", () => {
    rootSession = false;
    lastState = undefined;
    lastLabel = undefined;
    currentSessionName = undefined;
    clear();
  });
}
