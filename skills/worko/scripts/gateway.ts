// worko gateway —— 响应方常驻 daemon。
// 长连 hub WS，等别人来问(ask)，调本地 agent 答；只管 inbound ask，
// answer/note 不碰（那是发起方 ask.sh 自己轮询收）。空闲时挂在 socket 上睡，几乎不耗。
import { spawn } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { platform } from "node:os";

// 弹个桌面通知给机主：daemon 静默应答的话，机主根本不知道自己的 agent 被人拉起来跑过。
// 尽力而为：弹不出来（无桌面/无工具）就算了，console.log 仍在。WORKO_NOTIFY=0 可关。
function notifyUser(title, body) {
  if (process.env.WORKO_NOTIFY === "0") return;
  const t = title.replace(/"/g, "'"), b = body.replace(/"/g, "'");
  try {
    if (platform() === "darwin") spawn("osascript", ["-e", `display notification "${b}" with title "${t}"`], { stdio: "ignore" }).unref();
    else if (platform() === "linux") spawn("notify-send", [t, b], { stdio: "ignore" }).unref();
    // ponytail: Windows 原生 toast 要装 BurntToast 模块，不值当；靠下面的 console.log 兜底，真有人要再加。
  } catch { /* 通知失败不该影响应答 */ }
}

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
// WORKO_AGENT_CWD：本地 agent 在哪个目录里跑（codex 要在"已信任"的目录才肯非交互执行）。
const AGENT_CWD = process.env.WORKO_AGENT_CWD || undefined;
// WORKO_SANDBOX：codex 沙箱档位。默认 workspace-write = 盒子内可读/可跑命令/可写，
// 配 approval_policy=never → headless 永不弹批准、越界直接失败而不是吊死等人。谨慎者设 read-only。
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

// agent 没产出时，把退出码 + stderr 摘要带回去，便于排查（别只回干巴巴的占位符）。
const noOutput = (name, code, stderr) => {
  const e = stderr.trim().replace(/\s+/g, " ").slice(0, 300);
  return `[${name} 无输出 exit=${code}${e ? " | stderr: " + e : ""}]`;
};

// agent 适配层：每家 CLI 怎么调、回答从哪读，都收在这。
const adapters = {
  async mock() { return process.env.WORKO_MOCK_REPLY ?? `[mock ${ID}]`; },
  async claude(prompt, thread) {
    const s = await loadSessions(); const a = ["-p", "--output-format", "json"];
    if (s[thread]) a.push("--resume", s[thread]); a.push(prompt);
    const { stdout, stderr, code } = await run("claude", a);
    if (code === 127) return "[claude 未安装或不在 PATH]";
    try { const j = JSON.parse(stdout); if (j.session_id) { s[thread] = j.session_id; await saveSessions(s); } return (j.result ?? stdout).trim(); }
    catch { return stdout.trim() || noOutput("claude", code, stderr); }
  },
  async codex(prompt) {
    // --skip-git-repo-check：允许在非 git/非信任目录跑（codex 默认要求 git 仓库，否则拒绝执行）。
    // -s $SANDBOX + approval_policy=never：headless 命门——只要还会弹批准，无人应答就吊死。
    //   workspace-write 让盒子内的读/跑命令/写直接放行（如解 .docx），越界操作直接失败而非卡住。
    // -C $AGENT_CWD：把工作根 + 沙箱边界绑到这个目录。
    // 仍不暴露 danger-full-access：gateway 应答 workspace 里任何人，不给突破沙箱的口子。
    const a = ["exec", "--skip-git-repo-check", "-s", SANDBOX, "-c", "approval_policy=never"];
    if (AGENT_CWD) a.push("-C", AGENT_CWD);
    a.push(prompt);
    const { stdout, stderr, code } = await run("codex", a);
    if (code === 127) return "[codex 未安装或不在 PATH]";
    return stdout.trim() || noOutput("codex", code, stderr);
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
  const q = (ctx.recent?.at(-1)?.content ?? "").replace(/\s+/g, " ").slice(0, 120);
  console.log(`[${ID}] ↑ ${ctx.asker} 问你，正在拉起 ${AGENT}: ${q}`);
  notifyUser(`worko: ${ctx.asker} 在问你`, q || "（启动本地 agent 应答）");
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

// 重连退避：连不上/被拒时别 2s 死循环（会把自己 IP 刷进限流/封禁）。
// 成功连上就重置回 2s。
let retryMs = 2000;
const RETRY_MAX = 60_000;

function listen() {
  const ws = new WebSocket(`${WS_URL}/?id=${encodeURIComponent(ID)}&token=${encodeURIComponent(TOKEN)}`);
  ws.onopen = () => { retryMs = 2000; console.log(`[${ID}] connected ${WS_URL} (agent=${AGENT})`); catchUp(); };
  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    // 只对 inbound ask 动作；answer/note 一律忽略（那是我问出去的回信，发起方自己收）。
    if (m.type === "event" && m.event === "wake" && m.payload?.type === "ask") {
      console.log(`[${ID}] wake ask on ${m.payload.thread} (from ${m.payload.from})`);
      handleAsk(m.payload.thread).catch(console.error);
    }
  };
  ws.onclose = () => {
    console.log(`[${ID}] disconnected, retry ${retryMs / 1000}s（连不上多半是 token 没配好/还没被加进 workspace 白名单）`);
    setTimeout(listen, retryMs);
    retryMs = Math.min(retryMs * 2, RETRY_MAX);  // 指数退避，封顶 60s
  };
  ws.onerror = () => ws.close();
}

if (!ID || ID === "anon") { console.error("需要 WORKO_ID"); process.exit(1); }
listen();
