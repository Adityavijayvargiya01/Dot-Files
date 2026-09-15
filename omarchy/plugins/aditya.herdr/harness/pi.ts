// Traffic Herdr: report pi agent state to the shared status files.
// Lives in the Omarchy plugin; symlink into ~/.pi/agent/extensions/.

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

type AgentState = "working" | "blocked" | "idle";

const harness = "pi";
const agentId = `pi-${process.pid}`;
const pluginDir = join(
  process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
  "omarchy/plugins/aditya.herdr",
);
const reporter = join(pluginDir, "report-status");

function run(args: string[]): void {
  try {
    const child = spawn(reporter, args, { stdio: "ignore", detached: true });
    child.unref();
  } catch {
    // Status is best-effort; never break the session.
  }
}

function report(state: AgentState): void {
  run(["set", harness, agentId, state, String(process.pid)]);
}

function clear(): void {
  run(["clear", agentId]);
}

export default function (pi: any) {
  let rootSession = false;
  let agentActive = false;
  let promptCount = 0;
  let lastState: AgentState | undefined;

  function desired(): AgentState {
    if (promptCount > 0) return "blocked";
    if (agentActive) return "working";
    return "idle";
  }

  function publish(force = false): void {
    const next = desired();
    if (!force && next === lastState) return;
    lastState = next;
    report(next);
  }

  pi.on("session_start", async (_event: any, ctx: any) => {
    if (ctx?.mode !== "tui") return;
    rootSession = true;
    agentActive = ctx?.isIdle?.() === false;
    promptCount = 0;
    publish(true);
  });

  pi.on("agent_start", () => {
    if (!rootSession) return;
    agentActive = true;
    publish();
  });

  pi.on("agent_settled", (_event: any, ctx: any) => {
    if (!rootSession) return;
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
    clear();
  });
}
