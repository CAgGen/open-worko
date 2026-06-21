// open-worko 客户端：每人本地一个进程，拉推合一。
// 收 wake(推) → 把消息送进本机 agent 会话（首轮新建 / 回信 resume）
//            → 读 agent 输出，解析 "@对方: ..." → 发回(拉)。
// 不用 MCP、不用独立 daemon。node / bun 都能跑。
//
// 用法：
//   node client.ts                  # 监听 wake（常驻）。bun client.ts 同样可用。
//   node client.ts send <to> <内容>  # 主动发起一次提问

import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";

const HTTP = process.env.WORKO_URL ?? "http://localhost:8080";
const WS_URL = process.env.WORKO_WS ?? HTTP.replace(/^http/, "ws");
const ID = process.env.WORKO_ID ?? "claude_alice";
const TOKEN = process.env.WORKO_TOKEN ?? "";
const ROOM = process.env.WORKO_ROOM ?? "room_dev";
// 用哪种 agent：claude | codex | mock（不设则按 WORKO_MOCK 决定，默认 claude）
const AGENT = process.env.WORKO_AGENT ?? (process.env.WORKO_MOCK ? "mock" : "claude");
const SESSION_FILE = `.worko-sessions.${ID}.json`;

const authHeaders = TOKEN ? { authorization: `Bearer ${TOKEN}` } : {};

// —— thread ↔ 本机 session id 映射（resume 用，留在本地，不进服务器）——
async function loadSessions(): Promise<Record<string, string>> {
  try { return JSON.parse(await readFile(SESSION_FILE, "utf8")); }
  catch { return {}; }
}
async function saveSessions(s: Record<string, string>) {
  await writeFile(SESSION_FILE, JSON.stringify(s, null, 2));
}

async function postMessage(msg: Record<string, unknown>) {
  const res = await fetch(`${HTTP}/messages`, {
    method: "POST",
    headers: { "content-type": "application/json", ...authHeaders },
    body: JSON.stringify(msg),
  });
  return res.json();
}

// 跑一条命令，回 { stdout, code }
function run(cmd: string, args: string[]): Promise<{ stdout: string; code: number }> {
  return new Promise((resolve) => {
    let stdout = "";
    let p;
    try { p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] }); }
    catch { return resolve({ stdout: "", code: 127 }); }
    p.stdout.on("data", (d) => (stdout += d.toString()));
    p.on("error", () => resolve({ stdout: "", code: 127 }));
    p.on("close", (code) => resolve({ stdout, code: code ?? 0 }));
  });
}

// —— agent 适配层 —— 每家 CLI 怎么调、回答从哪读、怎么 resume，都收在这。
const adapters: Record<string, (prompt: string, thread: string) => Promise<string>> = {
  async mock(prompt) {
    return process.env.WORKO_MOCK_REPLY ?? `[mock ${ID}] 收到: ${prompt.slice(0, 60)}`;
  },

  // Claude Code：首轮 claude -p；回信 --resume 续接同一会话（记得上下文与初衷）
  async claude(prompt, thread) {
    const sessions = await loadSessions();
    const args = ["-p", "--output-format", "json"];
    if (sessions[thread]) args.push("--resume", sessions[thread]);
    args.push(prompt);
    const { stdout, code } = await run("claude", args);
    if (code === 127) return "[claude 未安装或不在 PATH]";
    try {
      const j = JSON.parse(stdout);
      if (j.session_id) { sessions[thread] = j.session_id; await saveSessions(sessions); }
      return (j.result ?? stdout).trim();
    } catch { return stdout.trim(); }
  },

  // Codex CLI：非交互 codex exec。注：resume 续接的精确写法待装上 codex 后核对。
  async codex(prompt) {
    const { stdout, code } = await run("codex", ["exec", prompt]);
    if (code === 127) return "[codex 未安装或不在 PATH]";
    return stdout.trim() || "[codex 无输出]";
  },
};

async function runAgent(prompt: string, thread: string): Promise<string> {
  const fn = adapters[AGENT] ?? adapters.claude;
  return fn(prompt, thread);
}

// 解析 agent 输出：取出 "@对方: ..." 当作要发的提问，其余文本当作回答。
function parseOutput(text: string) {
  const asks: Array<{ to: string; content: string }> = [];
  const rest: string[] = [];
  for (const line of text.split("\n")) {
    const m = line.match(/^@(\S+):\s*(.+)$/);
    if (m) asks.push({ to: m[1], content: m[2].trim() });
    else rest.push(line);
  }
  return { asks, answerText: rest.join("\n").trim() };
}

function buildPrompt(ctx: any): string {
  const lines = [
    `你在一个多 agent 协作房间里，你的身份是 ${ID}。`,
    `· 想向别的 agent 提问：单独写一行  @对方id: 你的问题`,
    `· 若下面有人在问你：直接给出回答（不要写 @）。`,
  ];
  if (ctx.head) lines.push(`\n[话题摘要]\n${ctx.head}`);
  lines.push("\n[最近消息]");
  for (const m of ctx.recent ?? []) lines.push(`${m.from} (${m.type}): ${m.content}`);
  return lines.join("\n");
}

async function onWake(payload: { thread: string; from: string; type: string }) {
  // daemon 只管"别人来问我"(ask)；answer/note 是我自己问出去的回信或闲话，
  // 由发起方的 `worko ask` 轮询去收，daemon 不碰，否则会把自己的回信重复处理。
  if (payload.type !== "ask") return;

  const thread = payload.thread;
  const ctx = await (await fetch(`${HTTP}/context?thread=${thread}`, { headers: authHeaders })).json();

  const output = await runAgent(buildPrompt(ctx), thread);
  const { asks, answerText } = parseOutput(output);

  // @对方: → 转发为新提问
  for (const a of asks) {
    await postMessage({ room: ROOM, thread, from: ID, to: [a.to], type: "ask", content: a.content });
    console.log(`[${ID}] → ask ${a.to}: ${a.content}`);
  }
  // 其余文本 → 回答给在等我的人（别回答自己）
  if (answerText && ctx.asker && ctx.asker !== ID) {
    await postMessage({ room: ROOM, thread, from: ID, to: [ctx.asker], type: "answer", content: answerText });
    console.log(`[${ID}] → answer ${ctx.asker}: ${answerText.slice(0, 80)}`);
  }
}

function listen() {
  const ws = new WebSocket(`${WS_URL}/?id=${encodeURIComponent(ID)}&token=${encodeURIComponent(TOKEN)}`);
  ws.onopen = () => console.log(`[${ID}] connected ${WS_URL}  (agent=${AGENT})`);
  ws.onmessage = (ev) => {
    let msg: any;
    try { msg = JSON.parse(ev.data as string); } catch { return; }
    if (msg.type === "event" && msg.event === "wake") {
      console.log(`[${ID}] wake on ${msg.payload.thread} (from ${msg.payload.from})`);
      onWake(msg.payload).catch(console.error);
    }
  };
  ws.onclose = () => { console.log(`[${ID}] disconnected, retry in 2s`); setTimeout(listen, 2000); };
  ws.onerror = () => ws.close();
}

// —— 阻塞式 ask：发问 → 等到对方 answer 再返回 ——
// 给"正在交互的 agent"用：一次调用走完一个来回，答案打到 stdout、诊断打到 stderr。
async function askAndWait(to: string, content: string, timeoutMs = 120_000): Promise<void> {
  const r = (await postMessage({ room: ROOM, from: ID, to: [to], type: "ask", content })) as { thread?: string };
  const thread = r.thread;
  if (!thread) { console.error(`[${ID}] 发起失败:`, r); process.exit(1); }
  console.error(`[${ID}] 已向 ${to} 提问 (thread=${thread})，等待回答…`);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise((res) => setTimeout(res, 1000));
    const ctx = await (await fetch(`${HTTP}/context?thread=${thread}`, { headers: authHeaders })).json();
    const ans = (ctx.recent ?? []).find(
      (m: any) => m.type === "answer" && Array.isArray(m.to) && m.to.includes(ID),
    );
    if (ans) { console.log(ans.content); return; }   // ← 文件/答案落到 stdout
  }
  console.error(`[${ID}] 等 ${to} 超时（${timeoutMs}ms）`);
  process.exit(1);
}

// —— 入口 ——
const [cmd, to, ...words] = process.argv.slice(2);
if (cmd === "ask") {
  await askAndWait(to, words.join(" "));          // 阻塞：问完等到答案才退出
} else if (cmd === "send") {
  const content = words.join(" ");
  const r = await postMessage({ room: ROOM, from: ID, to: [to], type: "ask", content });
  console.log(`[${ID}] sent ask to ${to}:`, r);
} else {
  listen();
}
