// worko gateway — responder-side persistent daemon.
// Keeps a long WebSocket connection to the hub, waits for inbound asks, calls the local agent,
// and posts the answer back. Only handles inbound asks; answer/note messages are ignored
// (the asker's ask.sh polls for those itself). Idles on the socket; nearly zero CPU when quiet.
import { spawn } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { platform } from "node:os";

// Notify the machine owner that the daemon answered silently on their behalf —
// otherwise they'd have no idea their agent was invoked. Best-effort: if no desktop
// or notification tool is available, console.log still runs. Set WORKO_NOTIFY=0 to disable.
function notifyUser(title, body) {
  if (process.env.WORKO_NOTIFY === "0") return;
  const t = title.replace(/"/g, "'"), b = body.replace(/"/g, "'");
  try {
    if (platform() === "darwin") spawn("osascript", ["-e", `display notification "${b}" with title "${t}"`], { stdio: "ignore" }).unref();
    else if (platform() === "linux") spawn("notify-send", [t, b], { stdio: "ignore" }).unref();
    // ponytail: Windows native toast requires the BurntToast module — not worth the dep; console.log covers it. Add when someone asks.
  } catch { /* notification failure must not affect the answer */ }
}

const HTTP = process.env.WORKO_URL ?? "http://localhost:8080";
const WS_URL = process.env.WORKO_WS ?? HTTP.replace(/^http/, "ws");
const ID = process.env.WORKO_ID ?? "anon";
const TOKEN = process.env.WORKO_TOKEN ?? "";
const ROOM = process.env.WORKO_ROOM ?? "";   // empty → server auto-resolves the workspace room via token (hardcoding room_dev causes 403)
const AGENT = process.env.WORKO_AGENT ?? "claude";   // local agent to use when queried: claude | codex | mock
const SESSION_FILE = process.env.WORKO_SESSIONS ?? `${process.env.HOME}/.worko/sessions.${ID}.json`;
const authHeaders = TOKEN ? { authorization: `Bearer ${TOKEN}` } : {};

async function loadSessions() { try { return JSON.parse(await readFile(SESSION_FILE, "utf8")); } catch { return {}; } }
async function saveSessions(s) { await mkdir(dirname(SESSION_FILE), { recursive: true }).catch(() => {}); await writeFile(SESSION_FILE, JSON.stringify(s, null, 2)); }

async function postMessage(msg) {
  const res = await fetch(`${HTTP}/messages`, {
    method: "POST", headers: { "content-type": "application/json", ...authHeaders }, body: JSON.stringify(msg),
  });
  return res.json();
}
// WORKO_AGENT_CWD: directory the local agent runs in (codex requires a "trusted" directory for non-interactive execution).
const AGENT_CWD = process.env.WORKO_AGENT_CWD || undefined;
// WORKO_SANDBOX: codex sandbox level. Default workspace-write = box can read/run commands/write inside;
// paired with approval_policy=never → headless mode never prompts for approval; out-of-scope operations fail immediately
// instead of hanging. Conservative users can set read-only.
const SANDBOX = process.env.WORKO_SANDBOX || "workspace-write";
function run(cmd, args) {
  return new Promise((resolve) => {
    let out = ""; let err = ""; let p;
    try { p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], cwd: AGENT_CWD }); } catch { return resolve({ stdout: "", stderr: "", code: 127 }); }
    p.stdout.on("data", (d) => (out += d.toString()));
    p.stderr.on("data", (d) => (err += d.toString()));
    p.on("error", () => resolve({ stdout: "", stderr: "", code: 127 }));
    p.on("close", (c) => resolve({ stdout: out, stderr: err, code: c ?? 0 }));
  });
}

// When the agent produces no output, include exit code + stderr summary for easier debugging.
const noOutput = (name, code, stderr) => {
  const e = stderr.trim().replace(/\s+/g, " ").slice(0, 300);
  return `[${name} no output exit=${code}${e ? " | stderr: " + e : ""}]`;
};

// Agent adapters: how to invoke each CLI and where to read the answer from.
const adapters = {
  async mock() { return process.env.WORKO_MOCK_REPLY ?? `[mock ${ID}]`; },
  async claude(prompt, thread) {
    const s = await loadSessions(); const a = ["-p", "--output-format", "json"];
    if (s[thread]) a.push("--resume", s[thread]); a.push(prompt);
    const { stdout, stderr, code } = await run("claude", a);
    if (code === 127) return "[claude not installed or not on PATH]";
    try { const j = JSON.parse(stdout); if (j.session_id) { s[thread] = j.session_id; await saveSessions(s); } return (j.result ?? stdout).trim(); }
    catch { return stdout.trim() || noOutput("claude", code, stderr); }
  },
  async codex(prompt) {
    // --skip-git-repo-check: allow running in non-git / non-trusted directories (codex refuses by default).
    // -s $SANDBOX + approval_policy=never: headless requirement — any pending approval dialog hangs forever with no one to click it.
    //   workspace-write lets the box read/run commands/write inside (e.g. unzip a .docx), failing immediately on out-of-scope ops.
    // -C $AGENT_CWD: bind working root + sandbox boundary to this directory.
    // danger-full-access is intentionally not exposed: the gateway answers anyone in the workspace;
    // there must be no remote path to break out of the sandbox.
    const a = ["exec", "--skip-git-repo-check", "-s", SANDBOX, "-c", "approval_policy=never"];
    if (AGENT_CWD) a.push("-C", AGENT_CWD);
    a.push(prompt);
    const { stdout, stderr, code } = await run("codex", a);
    if (code === 127) return "[codex not installed or not on PATH]";
    return stdout.trim() || noOutput("codex", code, stderr);
  },
};
const runAgent = (prompt, thread) => (adapters[AGENT] ?? adapters.claude)(prompt, thread);

function buildPrompt(ctx) {
  const L = [`You are in a multi-agent collaboration room, identified as ${ID}. Someone is asking you the following question — answer directly and concisely.`];
  if (ctx.head) L.push(`\n[Thread summary]\n${ctx.head}`);
  L.push("\n[Recent messages]");
  for (const m of ctx.recent ?? []) L.push(`${m.from} (${m.type}): ${m.content}`);
  return L.join("\n");
}

// Handle one inbound ask: call the local agent and post the answer back to the asker.
async function handleAsk(thread) {
  const ctx = await (await fetch(`${HTTP}/context?thread=${thread}`, { headers: authHeaders })).json();
  if (ctx.status !== "waiting") return;            // already answered / already closed → skip (dedup during catch-up)
  if (!ctx.asker || ctx.asker === ID) return;
  const q = (ctx.recent?.at(-1)?.content ?? "").replace(/\s+/g, " ").slice(0, 120);
  console.log(`[${ID}] ↑ ${ctx.asker} is asking you, spawning ${AGENT}: ${q}`);
  notifyUser(`worko: ${ctx.asker} is asking you`, q || "(spawning local agent to reply)");
  const answer = await runAgent(buildPrompt(ctx), thread);
  if (!answer) return;
  await postMessage({ ...(ROOM ? { room: ROOM } : {}), thread, from: ID, to: [ctx.asker], type: "answer", content: answer });
  console.log(`[${ID}] → answer ${ctx.asker}: ${answer.slice(0, 80)}`);
}

// Catch-up on reconnect: replay any threads still waiting_for me (prevents missed wakes during downtime).
async function catchUp() {
  try {
    const inbox = await (await fetch(`${HTTP}/inbox?id=${encodeURIComponent(ID)}`, { headers: authHeaders })).json();
    for (const t of inbox.threads ?? []) { console.log(`[${ID}] catch-up ${t}`); await handleAsk(t).catch(console.error); }
  } catch (e) { console.error("catchUp failed:", e.message); }
}

// Reconnect backoff: don't tight-loop when the hub is unreachable (avoids IP rate-limit / bans).
// Resets to 2 s on a successful connection.
let retryMs = 2000;
const RETRY_MAX = 60_000;

function listen() {
  const ws = new WebSocket(`${WS_URL}/?id=${encodeURIComponent(ID)}&token=${encodeURIComponent(TOKEN)}`);
  ws.onopen = () => { retryMs = 2000; console.log(`[${ID}] connected ${WS_URL} (agent=${AGENT})`); catchUp(); };
  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    // Only act on inbound asks; answer/note are replies to our own outbound asks — the asker collects those.
    if (m.type === "event" && m.event === "wake" && m.payload?.type === "ask") {
      console.log(`[${ID}] wake ask on ${m.payload.thread} (from ${m.payload.from})`);
      handleAsk(m.payload.thread).catch(console.error);
    }
  };
  ws.onclose = () => {
    console.log(`[${ID}] disconnected, retrying in ${retryMs / 1000}s (most likely cause: token not configured / not yet added to workspace allowlist)`);
    setTimeout(listen, retryMs);
    retryMs = Math.min(retryMs * 2, RETRY_MAX);  // exponential backoff, cap at 60 s
  };
  ws.onerror = () => ws.close();
}

if (!ID || ID === "anon") { console.error("WORKO_ID is required"); process.exit(1); }
listen();
