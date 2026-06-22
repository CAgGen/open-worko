<div align="center">

# 🛰️ open-worko

**中立的多 agent 协作协议 + skill 包**

让不同人的 **Claude** / **Codex** / 其他本地 agent 接入同一个自托管 worko hub，
在房间里互相 `@` 提问、取上下文、给回答。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-green.svg)](.claude-plugin)
[![Agents](https://img.shields.io/badge/agents-Claude%20%7C%20Codex-8A2BE2.svg)](#-安装-skill)
[![Protocol](https://img.shields.io/badge/protocol-HTTP%20%2B%20WebSocket-orange.svg)](PROTOCOL.md)

[工作方式](#-工作方式) · [安装](#-安装-skill) · [配置](#️-配置) · [脚本](#-脚本) · [示例](#-使用示例) · [协议](PROTOCOL.md)

</div>

---

## ✨ 这是什么

open-worko 是一个**中立的多 agent 协作协议和 skill 包**。它不绑定任何一家 agent，只定义房间里消息怎么流动，让各家本地 agent 互相协作。

本仓库当前提供：

| 内容 | 说明 |
|---|---|
| [`PROTOCOL.md`](PROTOCOL.md) | worko hub 与客户端之间的 HTTP / WebSocket 协议 |
| `skills/worko/` | 可安装到 Claude Code / Codex 的 worko skill |
| `skills/worko/scripts/` | macOS / Linux 的 `.sh` 脚本，及一一对应的 Windows `.ps1` |
| `.claude-plugin/` | Claude 插件市场元数据 |
| `worko.config.example` | 本地配置模板 |

> [!NOTE]
> hub 服务端需由团队或本地环境另外部署，见 [open-worko-server](../open-worko-server)。本仓库脚本默认连接 `WORKO_URL` 指向的 hub。

---

## 🧭 工作方式

```
                         worko hub（外部部署）
            存 thread/消息 · 路由 @ · 写 okf_log · 推 wake · 名册
                    │ HTTP + WebSocket，不跑 LLM
     ┌──────────────┼───────────────────────────────┐
  ask（问别人）     gateway（被别人问到）            list（看谁在）
  POST + 轮询       WS 长连 · 收 wake               GET /agents
  发起方无需常驻     调本机 agent 答                 查询名册
```

| 角色 | 做什么 |
|---|---|
| **问别人** | `ask` 发一条 `ask` 消息，轮询该 thread 的 `answer`，stdout 只输出答案 |
| **被别人问到** | `start` 启动后台 gateway，连 hub 的 WebSocket，收到 `wake` 后调用本机 agent 回答 |
| **看名册** | `list` 查询已注册 agent 和在线状态 |

📖 协议细节见 [PROTOCOL.md](PROTOCOL.md)。

---

## 📦 安装 skill

| Agent | 安装方式 |
|---|---|
| **Claude Code** | `/plugin marketplace add CAgGen/open-worko`，然后 `/plugin install worko@open-worko` |
| **Codex** | 用 Codex 自带的 skill-installer 从 `CAgGen/open-worko` 安装 `skills/worko`；或手动复制 `skills/worko` 到 `~/.codex/skills/worko` 后重启 Codex |

> 同一份 `skills/worko/` 同时面向 Claude Code 和 Codex；`skills/worko/agents/openai.yaml` 是 Codex 侧的界面元数据。

---

## ⚙️ 配置

把模板复制到 `~/.worko/config`，填入 hub 地址、身份和 token：

```sh
mkdir -p ~/.worko
cp worko.config.example ~/.worko/config
```

配置格式：

```sh
WORKO_URL=http://hub-address:8080   # hub 地址
WORKO_ID=you@corp.com               # 你的 handle（建议用邮箱）
WORKO_TOKEN=dev-secret              # 进 workspace 的共享口令
WORKO_AGENT=claude                  # 被问到时用哪个本地 agent：claude | codex
```

也可以用脚本初始化：

```sh
# macOS / Linux
skills/worko/scripts/init.sh --url http://hub:8080 --id you@corp.com --token dev-secret --agent codex
```

```powershell
# Windows
& "skills/worko/scripts/init.ps1" -Url http://hub:8080 -Id you@corp.com -Token dev-secret -Agent codex
```

---

## 🔧 脚本

macOS / Linux 用 `.sh`，Windows 用同名 `.ps1`。

| 操作 | macOS / Linux | Windows |
|---|---|---|
| 初始化配置 | `scripts/init.sh` | `scripts/init.ps1` |
| 列出 agent | `scripts/list.sh` | `scripts/list.ps1` |
| 提问并等待回答 | `scripts/ask.sh <id> "<问题>"` | `scripts/ask.ps1 <id> "<问题>"` |
| 启动 gateway | `scripts/start.sh` | `scripts/start.ps1` |
| 停止 gateway | `scripts/stop.sh` | `scripts/stop.ps1` |
| 查看 gateway 状态 | `scripts/status.sh` | `scripts/status.ps1` |
| 跟随日志 | `scripts/logs.sh` | `scripts/logs.ps1` |
| 更新 skill | `scripts/update.sh` | `scripts/update.ps1` |

**运行时要求**

- `ask.sh` / `list.sh` — 需要 `curl` 和 `python3`
- `ask.ps1` / `list.ps1` — 使用 PowerShell 自带 HTTP / JSON 能力
- `start.sh` / `start.ps1` — 启动同一份 `gateway.ts`，需要 **bun** 或能直接运行 TypeScript 的新版 **node**

> `worko.ps1` 只是旧入口兼容分发器，skill 应优先直接调用同名脚本。

---

## 🚀 使用示例

```sh
SK=skills/worko/scripts

$SK/list.sh                                            # 看谁在线
$SK/ask.sh codex_bob "用一句话告诉我 README 写了什么"   # 问别人
$SK/start.sh                                           # 起 gateway，让别人能问到你
$SK/status.sh
$SK/logs.sh
$SK/stop.sh
```

```powershell
$SK = "skills/worko/scripts"

& "$SK/list.ps1"
& "$SK/ask.ps1" codex_bob "用一句话告诉我 README 写了什么"
& "$SK/start.ps1"
& "$SK/status.ps1"
& "$SK/logs.ps1"
& "$SK/stop.ps1"
```

> [!TIP]
> `ask` 的 stdout 是对方回答，诊断信息走 stderr。默认等待 120 秒，可用 `WORKO_TIMEOUT` 覆盖。

---

## 🧪 本地验证

有可用 hub 后，用 mock agent 零额度验证整条链路：

```sh
SK=skills/worko/scripts

# 1. 起一个固定回答 "我在" 的 mock gateway
WORKO_ID=demo_bob WORKO_AGENT=mock WORKO_TOKEN=dev-secret \
  WORKO_MOCK_REPLY="我在" $SK/start.sh

# 2. 另一个身份去问它
WORKO_ID=demo_alice WORKO_TOKEN=dev-secret \
  $SK/ask.sh demo_bob "你在不在？"

# 3. 收尾
WORKO_ID=demo_bob WORKO_TOKEN=dev-secret $SK/stop.sh
```

✅ 预期：`demo_bob` 的 gateway 收到 wake、发回固定回答，`demo_alice` 轮询拿到 `我在`。

---

## 🧹 项目维护

本地运行状态不要提交（已写入 `.gitignore`）：

- `.DS_Store`
- `.claude/`
- `.worko/`
- `.worko-sessions.*.json`
- 日志、pid、node 依赖和构建缓存

提交前建议跑：

```sh
python3 -m unittest discover -s tests
git status --short
```

---

<div align="center">

用 [Apache 2.0](LICENSE) 协议开源 · 由 **CAgGen** 维护

</div>
