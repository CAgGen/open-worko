// worko gateway —— 响应方常驻 daemon。
// 长连 hub WS，等别人来问(ask)，调本地 agent 答；只管 inbound ask，
// answer/note 不碰（那是发起方 ask.sh 自己轮询收）。空闲时挂在 socket 上睡，几乎不耗。
import { spawn } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const HTTP = process.env.WORKO_URL ?? "http://localhost:8080";
const WS_URL = process.env.WORKO_WS ?? HTTP.replace(/^http/, "ws");
const ID = process.env.WORKO_ID ?? "anon";
const TOKEN = process.env.WORKO_TOKEN ?? "";
const ROOM = process.env.WORKO_ROOM ?? "";   // 留空 → 服务器按 token 自动定位 workspace 的 room（乱填 room_dev 会 403）
const AGENT = process.env.WORKO_AGENT ?? "claude";   // 被问到时用哪个本地 agent：claude | codex | mock
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
function run(cmd, args) {
  return new Promise((resolve) => {
    let out = ""; let p;
    try { p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] }); } catch { return resolve({ stdout: "", code: 127 }); }
    p.stdout.on("data", (d) => (out += d.toString()));
    p.on("error", () => resolve({ stdout: "", code: 127 }));
    p.on("close", (c) => resolve({ stdout: out, code: c ?? 0 }));
  });
}

// agent 适配层：每家 CLI 怎么调、回答从哪读，都收在这。
const adapters = {
  async mock() { return process.env.WORKO_MOCK_REPLY ?? `[mock ${ID}]`; },
  async claude(prompt, thread) {
    const s = await loadSessions(); const a = ["-p", "--output-format", "json"];
    if (s[thread]) a.push("--resume", s[thread]); a.push(prompt);
    const { stdout, code } = await run("claude", a);
    if (code === 127) return "[claude 未安装或不在 PATH]";
    try { const j = JSON.parse(stdout); if (j.session_id) { s[thread] = j.session_id; await saveSessions(s); } return (j.result ?? stdout).trim(); }
    catch { return stdout.trim(); }
  },
  async codex(prompt) {
    const { stdout, code } = await run("codex", ["exec", prompt]);
    if (code === 127) return "[codex 未安装或不在 PATH]";
    return stdout.trim() || "[codex 无输出]";
  },
};
const runAgent = (prompt, thread) => (adapters[AGENT] ?? adapters.claude)(prompt, thread);

function buildPrompt(ctx) {
  const L = [`你在一个多 agent 协作房间里，身份是 ${ID}。有人在问你下面的问题，请直接、简洁地回答。`];
  if (ctx.head) L.push(`\n[话题摘要]\n${ctx.head}`);
  L.push("\n[最近消息]");
  for (const m of ctx.recent ?? []) L.push(`${m.from} (${m.type}): ${m.content}`);
  return L.join("\n");
}

// 处理一条"别人问我"的 thread：调本地 agent，把答案发回提问方。
async function handleAsk(thread) {
  const ctx = await (await fetch(`${HTTP}/context?thread=${thread}`, { headers: authHeaders })).json();
  if (ctx.status !== "waiting") return;            // 已答过/已结束 → 跳过（补同步时去重）
  if (!ctx.asker || ctx.asker === ID) return;
  const answer = await runAgent(buildPrompt(ctx), thread);
  if (!answer) return;
  await postMessage({ ...(ROOM ? { room: ROOM } : {}), thread, from: ID, to: [ctx.asker], type: "answer", content: answer });
  console.log(`[${ID}] → answer ${ctx.asker}: ${answer.slice(0, 80)}`);
}

// 重连补同步：上线先把"还 waiting_for 我"的 thread 补答一遍（防断线那几秒丢 wake）。
async function catchUp() {
  try {
    const inbox = await (await fetch(`${HTTP}/inbox?id=${encodeURIComponent(ID)}`, { headers: authHeaders })).json();
    for (const t of inbox.threads ?? []) { console.log(`[${ID}] 补同步 ${t}`); await handleAsk(t).catch(console.error); }
  } catch (e) { console.error("catchUp 失败:", e.message); }
}

function listen() {
  const ws = new WebSocket(`${WS_URL}/?id=${encodeURIComponent(ID)}&token=${encodeURIComponent(TOKEN)}`);
  ws.onopen = () => { console.log(`[${ID}] connected ${WS_URL} (agent=${AGENT})`); catchUp(); };
  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    // 只对 inbound ask 动作；answer/note 一律忽略（那是我问出去的回信，发起方自己收）。
    if (m.type === "event" && m.event === "wake" && m.payload?.type === "ask") {
      console.log(`[${ID}] wake ask on ${m.payload.thread} (from ${m.payload.from})`);
      handleAsk(m.payload.thread).catch(console.error);
    }
  };
  ws.onclose = () => { console.log(`[${ID}] disconnected, retry 2s`); setTimeout(listen, 2000); };
  ws.onerror = () => ws.close();
}

if (!ID || ID === "anon") { console.error("需要 WORKO_ID"); process.exit(1); }
listen();
