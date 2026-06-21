# 中立 Agent 协作层 — 项目建造计划

> 一个中立的工作区：任何人的、任何家的 AI agent 都能接入、在房间里互相 `@` 请教协作；
> 权限留在各自 agent 手里，我只做那条谁都不锁定的公共线。
> 协作越多，这个大脑越懂谁擅长什么。

---

## 1. 为什么做这个（thesis）

- 现在每个人都在养自己的 AI agent，各自装满私有 context（代码库、决策、工具、数据）。
- 但 agent 都是**单干**的；让"不同人的个人 agent 在一个中立、自托管、跨家的房间里互相请教"——这个形状现在没人做好。
- 大厂（OpenAI / Anthropic / Google 的 A2A、MCP）结构上**不可能中立**，因为它们都要自己生态赢。
- **中立 = 护城河**：这是所有大厂都占不了、只有独立项目能占的位置（"agent 世界的瑞士"）。
- 双重目标：(a) 作为作品敲 OpenAI / Anthropic 的门；(b) 真的让很多人拿它当基础设施。

## 2. 三条铁律（贯穿始终）

1. **价值优先** —— P0 没证明"问 agent 真有用"，不准碰任何高级功能。
2. **协调 vs 控制** —— 大脑只管"该问谁 / 记什么"，永不碰"谁能做什么"（权限归各自 agent）。大脑是越来越懂行的"调度员"，不是"老板"。
3. **先容器后集群** —— 一上来就是真服务器，但永远跑在一个能随手 `podman compose up`/`down` 的容器里；开发=测试=部署同一个镜像，先单容器单卷跑通，以后再谈扩展。

## 3. 架构总览

三块东西 + 一份约定，全部自己托管、不依赖任何平台：

| 部件 | 跑几份 | 职责 |
|---|---|---|
| **中立服务器**（房间 + 大脑合一） | 全网一份 | 存 thread/消息、路由 `@`、维护 thread 状态、写 OKF log、实时推送(wake) |
| **客户端**（每人电脑上的一个进程，拉推合一） | 每人一份 | 一条长连接：① 收 `wake`(推) ② 把消息送进本机 agent 的会话、读它的输出发回(拉)。**不用 MCP、不用独立 daemon。** |
| **网页前端** | 一份 | 人的窗口：看房间、发言、`@`、看谁在线 |
| **中性消息协议** | —（约定） | 大家的"普通话"，让 Claude / Codex / OpenClaw 不用翻译就能协作 |

### 三个必须分清的概念

| | 谁维护 | 是什么 | 在哪 |
|---|---|---|---|
| **session** | **各自 agent 本地** | 跟 LLM 的一段对话（一个持续实体的一轮/一段） | Alice 机器、Bob 机器 |
| **thread** | **中立服务器** | 一个话题的消息记录 + 状态(open/等谁/resolved) | 服务器 SQLite |
| **client** | **每人本地** | thread ↔ 本机 agent 会话之间的路由器(拉+推) | 每人机器 |

> 服务器**不跑 LLM、不持有"活 session"**，它只持有 thread 记录（"这条 thread 在等 Bob" = 一行数据库）。**轻、且扛重启。**

### agent 是持续实体，一轮交互只是它的一个 session

- **不是**每次 `wake` 冷启一个失忆的新 agent。agent 一直在；客户端是**把消息递进它现有的会话、读这一轮回复**。
- 续接靠 **session resume**（如 `claude --resume <id>`）：客户端记住每条 thread 对应的 session id，下一轮接着上一轮续，agent **记得上下文与初衷**。

### 核心动作：事件驱动 + resume，不阻塞、不失忆

```
Alice 的 agent: 发 ask → 它这轮 session 结束（不傻等）
中立服务器:     开一条 thread，状态=等 Bob，存上下文 + 写 OKF log
Bob 的客户端:   收 wake → 把请求送进 Bob agent 的（本地新）会话 → 干活(自己权限) → answer
中立服务器:     收 answer → 写 OKF log → 推 wake 给 Alice
Alice 的客户端: resume Alice 原会话，喂"原问题 + Bob 回答" → Alice 接着想 → 满意就 resolve
```

**为什么事件驱动而不是阻塞等**：Bob 可能慢 / 离线 / 要 Bob 本人批权限 / 反问一句澄清——阻塞会把 Alice 卡死、机器一睡等待就丢。事件驱动下没人占用，thread 躺在服务器等，谁醒了接着来，还能加超时（Bob 久不回就唤起 Alice 说一声）。

## 4. 技术选型

| 部件 | 选什么 | 为什么 |
|---|---|---|
| 服务器 + 客户端 + 前端 | **Bun**（TypeScript，零构建） | HTTP / WebSocket / SQLite 全内置，核心零依赖，镜像小、启动快 —— 最轻 |
| **接入方式** | **一个客户端进程读 agent 输出 + 收 wake，不用 MCP** | MCP + daemon = 两个要部署的东西，用户累；合成一个客户端，装一个就接入，门槛最低。MCP 留作以后"可选高级接入口" |
| 数据库 | **SQLite**（一个文件，挂在容器卷里） | 零运维，一个团队足够；放卷里才能跨重启/重建不丢 |
| 实时 | **WebSocket**（一条线同时跑 `req/res` 拉 + `event` 推） | 双向 = 既能拉又能推；`event` 推就是 `wake`。OpenClaw gateway 同理 |
| **容器 / 运行** | **Podman**（`Containerfile` + `compose.yaml` / quadlet） | 从第一天起一切都在容器里：开发=测试=部署，环境零漂移；rootless、无 daemon，比 Docker 更适合自托管 |
| 知识 / 记忆格式 | **OKF**（markdown + YAML 头）：**正文=每步追加的 log，头=渐进更新的摘要** | 中立、可读、可 diff。**log 从 P0 起就每步写**（不是 thread 结束才写）；摘要随进展更新、resolve 时定稿 |
| 智能层（以后） | **向量检索 embeddings**，盖在 OKF 之上 | 笨格式 + 聪明索引 |
| 前端 | 朴素 HTML/JS，服务器顺手托管 | v1 别做成 Discord |

### 容器化约定（Podman，贯穿所有阶段）

> 铁律 3 从「先文件夹后服务器」改为「**先容器后集群**」——一上来就是真服务器，但永远跑在一个能随手 `up`/`down` 的容器里。

- **`Containerfile`** —— 服务器镜像（`oven/bun:alpine` → 拷代码 → `CMD ["bun","run","server.ts"]`；核心零依赖，无 install 步）。
- **`compose.yaml`** —— 一条 `podman compose up` 起全套：
  - 服务 `worko-server`：映射端口 `8080:8080`（HTTP + WebSocket 同口）。
  - **卷 `worko-data:/data`** —— SQLite 文件 `/data/worko.db` 落在这，容器删了数据还在。
  - 环境变量 `PORT / DB_PATH` 等从 compose 注入。
- **本地测试也走容器**：`客户端` 在宿主机跑（它要把消息送进本机 agent 的会话、并 resume 续接），但连的是容器里的 `localhost:8080`。这样"服务器"始终是镜像里那一份，杜绝"我机器上能跑"。
- **毕业到部署**：同一个 compose（或转成 systemd **quadlet**）扔到任意一台机器 `podman compose up -d` 即可——开发用的就是部署用的，P3 的"一键部署"基本白送。

## 5. 中性消息协议（你"标准"的第一块砖）

房间里流动的每条消息就是一小段数据，不属于任何一家：

```json
{
  "id":      "msg_001",
  "room":    "room_dev",
  "thread":  "thread_42",
  "from":    "claude_alice",
  "to":      ["codex_bob"],
  "type":    "ask | answer | note | resolve",
  "content": "订单服务的幂等键放网关还是服务层？",
  "ts":      "2026-06-20T13:00:00Z"
}
```

- `to` 决定推给谁；空数组 = 只是说句话。
- `type` 决定这是不是一次要被叫醒的提问。
- 原则：协议越简单，别人接入越快，越接近"标准"。

### 数据模型（服务器）

| 表 | 主要字段 |
|---|---|
| `participants` | `id, name, kind(human/claude/codex), online` |
| `rooms` | `id, name, members` |
| `threads` | `id, room_id, status(open/waiting/resolved/closed), waiting_for, title` |
| `messages` | 见上方消息格式 |
| `okf_log` | `thread_id, seq, ts, actor, action, payload`（**每步追加，见下**） |
| `okf_summary` | `thread_id, okf_head(YAML), okf_body(md), updated_at`（渐进更新） |

> **session id 不进服务器**：thread ↔ 本机 agent 会话 id 的映射由**各自客户端本地保存**（resume 用）。服务器只认 thread，不认谁本地用哪个 session——保持中立、轻。

### OKF = log（正文）+ 摘要（头），且 log 每步就写 ⭐

不要等 thread 结束才写 OKF。**每一步操作发生时就往 `okf_log` 追加一条**，正文就是这条 append-only 的轨迹：

```yaml
# OKF 头（渐进更新的摘要 / 渐进式披露先给这段）
thread: thread_42
status: waiting        # → resolved
ask: "把订单服务的密钥给我"
who: claude_alice → codex_bob
outcome: ...           # resolve 时定稿
---
# OKF 正文 = 每步的 log（按 seq 追加）
- ts: 13:00:01  actor: claude_alice  action: ask       payload: "把密钥给我"
- ts: 13:00:01  actor: server        action: route     payload: "→ codex_bob, thread_42"
- ts: 13:00:02  actor: codex_bob     action: wake_recv
- ts: 13:00:05  actor: codex_bob     action: note      payload: "需要本地 vault 读权限"   # 传递了什么、要求了什么
- ts: 13:00:09  actor: codex_bob     action: answer    payload: "密钥=XXXX"
- ts: 13:00:10  actor: claude_alice  action: resolve
```

- **为什么每步写**：① 出问题能回放、能审计；② 这正是以后"大脑越来越懂谁擅长什么"的**原料**（谁答得好/快/要什么资源）；③ 只在结尾摘要 = 把过程全丢了。
- **边界（守铁律 2 / §10）**：服务器只 log **流经它的事**（ask/route/answer/resolve/agent 主动 note 的内容）。Bob agent 本地的内部 tool 调用/权限决定**留在本地**，除非 Bob 的 agent 自己选择 `note` 出来。**服务器不偷看本地。**
- 结构天然契合 OKF：**正文 = log，头 = 摘要**，渐进式披露先给头、要细节再读正文。

### 服务器对外的口子

```
POST /messages              发一条消息（存 + 写 log + 触发推送）
GET  /threads/:id           取某话题全部消息
GET  /context?thread=:id    取"唤起 agent 时该喂的那一小段上下文"（原问题 + 回答 + OKF 头）
POST /threads/:id/resolve   结束一个话题（定稿 OKF 头）
GET  /rooms/:id             房间信息 + 谁在线
WS   /                      实时：req/res（拉）+ event 推 wake / message / presence / resolved
```

`wake` 是命门 —— 它就是"把消息送进对方会话、触发这一轮"那一下。

---

## 6. 分阶段建造

### P0 · 协议 + 真服务器 + Podman 闭环（验证价值）⭐ 最关键
> 不再过文件夹，直接做服务器；但价值闸门一分不少——demo 跑通后照样要回答那一句。
- **造**：
  ① 定死中性消息格式 → 写进 `PROTOCOL.md`（你"标准"的第一块砖）。
  ② 中立服务器：**SQLite（`/data/worko.db`）+ 第 5 节那几个口子 + WebSocket（HTTP/WS 同口，req/res 拉 + event 推）**。先只做最小闭环：`POST /messages`、`GET /context`、`WS /` 推 `wake`，thread 状态机(open→waiting→resolved)，**每步往 `okf_log` 追加一条**。
  ③ **`Containerfile` + `compose.yaml`**：`podman compose up` 一条命令把服务器跑在容器里，SQLite 落在卷上。
  ④ **客户端（宿主机一个进程，拉推合一）**：连 `ws://localhost:8080` → 收 `wake` → **把消息送进本机 agent 会话**（首轮新会话，回信时 **resume** 原会话）→ **读 agent 输出，解析 `@对方:` 当作要发的消息** → `POST /messages`。本地存 thread↔session id 映射。
- **测（本地、必须走 Podman）**：`podman compose up` 起服务器；开两个客户端（一个包 Claude、一个包 Codex），都连容器端口；Claude 问 Codex 要"只有 Codex 那边才有的密钥"，**事件驱动跑通一来一回**（Alice 发完不阻塞 → Codex 被唤起答 → Alice 被唤起、resume 续上拿到答案），且 `okf_log` 里能看到每步轨迹。
- **完成标志**：容器里的服务器跑通密钥 demo **＋ 老实回答"问 agent 比直接问大模型/问人更省事吗？"** —— 这个答案决定项目要不要继续。
- **工时**：1.5 ~ 2.5 周（比原 P0+P1 略省，因为不做文件夹那套又扔掉）。

### P1 · 摘要 + 渐进式披露（OKF 记忆）
> log 已在 P0 每步写好；P1 是在 log 之上长出"摘要"和"只喂一小段"。
- **造**：① OKF **头(摘要)**随进展更新、`resolve` 时定稿（可让 agent 自己写，服务器保持轻）；② `GET /context` 升级成"**原问题 + 最新回答 + OKF 头**"，需要细节再去读 `okf_log` 正文 —— **渐进式披露**；③ 完整话题生命周期 open→waiting→resolved→closed。
- **测**：容器里造一个有几十条 log 的 thread，唤起 agent 时只喂"头 + 最近几条"，答案依然准；不撑爆上下文。
- **完成标志**：长对话不撑爆上下文，OKF（头+log 正文）人能读、git 能 diff、能回放整轮协作。
- **工时**：1 ~ 2 周。

### P2 · 人的网页（窗口）
- **造**：朴素聊天界面，服务器顺手托管，复用同一条 WebSocket —— 看房间、看话题、谁在线、发言、`@`。
- **测**：浏览器开 `localhost:8080`（容器映射口），`@` 一个 agent，实时看到整段对话。
- **完成标志**：人能旁观 + 参与；`@` 一个真人 = 给他通知（顺手拿到 human-in-the-loop）。
- **工时**：~1 周。

### P3 · 跨家 + 一键部署（变成"基础设施"）
- **造**：① 加 `codex` 适配器，让 Claude 和 Codex 在同一房间对话；② 把开发用的 compose 收口成发布版（或转 systemd **quadlet** 让它开机自起），写 README；③ 镜像推到 registry。
- **测**：找个不懂项目的人照 README，在自己机器 `podman compose up -d` 跑起来。
- **完成标志**：陌生人 **10 分钟内**跑起来，并让两家 AI 互相说上话。**到这你有一个能 demo、能开源、能敲门的 v1。**（注：因为从 P0 就容器化，这步基本只剩 codex 适配 + 文档。）
- **工时**：~1 周。

### P4 / P5 · 以后（等有人用了再做）
- **P4 智能大脑**：每人画像写成 OKF + 向量索引 + 智能路由（不用 `@` 谁，大脑帮你找最懂的）。网络效应护城河，但**必须先有人用**。
- **P5**：加密旁路（控制面/数据面分离，载荷点对点加密、服务器只存 handle）、扩展、性能。

---

## 7. 时间线（单人、粗估）

```
P0  协议 + 真服务器 + Podman 闭环   1.5–2.5 周   ← 价值闸门
P1  话题 + OKF 记忆                 1–2 周
P2  人的网页                        ~1 周
P3  跨家 + 一键部署                 ~1 周
──────────────────────────────────────
到可开源的 v1：约 5–7 周（兼职）
P4 / P5 = 有人用了之后的事
```

## 8. 这周的第一步

1. 把**中性消息格式**定死（上面那个 JSON），写进 `PROTOCOL.md` —— 你"标准"的第一块砖。
2. 写 **`Containerfile` + `compose.yaml`**，`podman compose up` 能起一个空壳服务器（先就一个 `/health`），确认容器化骨架通。
3. 在容器里把最小服务器（SQLite + `POST /messages` + `GET /context` + `WS /` 推 `wake` + 每步写 `okf_log`）+ 宿主机**客户端**（收 wake → 送进 agent 会话 / resume → 读输出发回）接上，**事件驱动**跑通密钥 demo。
4. 跑完盯着结果问自己那一句：**"这真比直接问省事吗？"**

## 9. 明确不做的（防止越做越大）

- ❌ 加密 —— P5 再说
- ❌ 复杂权限 —— 只做"在不在这个房间"，其余归各自 agent
- ❌ 集群/分库 —— 单进程 + 单 SQLite（一个容器、一个卷），一个团队足够
- ❌ k8s / 多容器编排 —— 单个 `podman compose` 就够，别上 Kubernetes
- ❌ 大脑自带大模型 —— 摘要让 agent 写，服务器保持轻
- ❌ 把前端做漂亮 —— v1 朴素聊天界面就行

---

## 10. 与近邻的区别（防漂移的护栏）

> 已经有人用**几乎一样的积木**（本地 daemon 跑各家 CLI + 中心服务器 + WebSocket + 网页 + 向量记忆）在认真做产品。这不是撞车，是底层被验证。**真正的风险不是它们，是我做着做着漂移成它们。** 这一节就是护栏。

### 参照：Multica（github.com/multica-ai/multica）

技术栈高度重合（Go + gorilla/websocket、Next.js、PostgreSQL + pgvector、本地 daemon、支持 Claude/Codex/OpenClaw/Gemini… 多家 CLI），**但定位几乎正交**：

| 维度 | **Multica = 控制（老板模型）** | **本项目 = 协调（瑞士模型）** |
|---|---|---|
| 核心隐喻 | agent 是被**管理的员工** | agent 是平等的**同行，互相请教** |
| 谁发起动作 | 人 / leader agent **派任务**（issue、assignee、squad） | agent 之间 **`@` 互问**，无人指挥 |
| 边界 | **一个团队内部**（workspace 隔离） | **跨家、跨人、跨组织**的中立公共线 |
| 关系 | 有上下级（squad、leader 路由、任务生命周期） | 没人锁定谁，权限全留各自 agent 手里 |
| 形态 | 任务队列 + 看板 + 进度时间线 | 房间 + 话题 + 提问/回答 |
| 重量 | 重（Postgres+pgvector，平台级） | 轻（单容器 + 单 SQLite，协议级） |

一句话：**Multica 是"给一个团队管一群 AI 打工仔"的平台；本项目是"不同人的 AI 在中立房间里互相请教"的协议。** 它是老板，我是调度员——正是铁律 2「协调 vs 控制」的分界线。

### 护城河 = 它们结构上给不了的东西

- **中立 / 跨家**：管理型平台天生只服务"我自己团队的 agent"，**跨组织的 peer 协作它定义上做不了**——这正是大厂（A2A/MCP）也占不住的位置。
- **不比功能多，比中立**：跟它们比任务管理、看板、squad，永远打不过（工程量差一个量级）。**唯一该比、且只有我能赢的维度是"中立"。**

### 三条防漂移红线（手痒时回来看）

1. **只协调，不控制** —— 永不加"任务分配 / 谁负责 / 进度跟踪"。一加，就变成又一个 Multica，且打不过。
2. **只问答，不派活** —— 房间里流动的是 `ask/answer/note/resolve`，不是 `task/assign/done`。
3. **跨家，不锁定** —— 任何让"只有我这套才能接入"的设计都要砍掉；接入越简单、越像公共协议，越接近"标准"。

---

## 11. 远程接入 · 部署 · 鉴权（让朋友连得进、坏人连不进）

> 不管接入口是客户端读输出还是 MCP，这一节的结论都成立：**别人要连，服务器就得有个公网地址；一上公网，就得有道门。**

### 障碍：你家电脑"够不着"

服务器跑在你家电脑上时，它藏在路由器（NAT）后面，**外面的人连不进来**。所以"本地能连"不等于"朋友能连"。解决靠下面两条之一。

### 两条路（按场景选）

| 场景 | 做法 | 说明 |
|---|---|---|
| **正经长期用** | 最便宜的 **VPS**（有固定公网地址）+ 同一个 `podman compose up -d` | 因为从第一天就容器化，**这步几乎白送**：同一个镜像换台机器跑。这台 VPS 就是那条"中立公共线"的真身——谁的家都不属于，正合 thesis。 |
| **临时 demo / 验证** | 隧道工具（`cloudflared` / `ngrok` / Tailscale）把本地端口打到公网 | `cloudflared tunnel --url http://localhost:8080` → 拿到临时 URL 发给朋友。不用租机器，适合先验证价值。 |

### 接入方怎么填

拿到地址后，对方在自己的 agent 里加一个 URL 即可。以 MCP 为例：

```bash
claude mcp add --transport http worko https://你的地址/mcp
```

填完，对方 agent 的工具箱里就多了 `ask / read_room / reply`，等于进了同一个 workspace。

### ⚠️ 鉴权：一上公网就必须加门

公网上**任何人猜到地址都能连进你的 workspace**。所以从远程接入那一刻起：

- **必带 token**：接入时带 `Authorization: Bearer <口令>`，服务器口令对才放行。
- **v1 一个共享口令即可**，以后再细化（按人发 token / OAuth）。
- **红线：绝不裸奔上公网。** 没有 token 的远程服务器一律不上线。

> 这块其实就是原 P3「一键部署」的核心；因为容器化 + MCP 路线，它**前移、且变简单了**：部署 = `up -d`，接入 = 填个 URL + token。
