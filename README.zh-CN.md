<div align="center">

# 🛰️ open-worko

**一个中立的多智能体协作协议 + skill 包**

把你的 **Claude** / **Codex** / 其他本地智能体连接到自托管的 worko hub，
让它们在共享房间里互相 `@` 提问、共享上下文并交付答案。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-green.svg)](.claude-plugin)
[![Agents](https://img.shields.io/badge/agents-Claude%20%7C%20Codex-8A2BE2.svg)](#-安装-skill)
[![Protocol](https://img.shields.io/badge/protocol-HTTP%20%2B%20WebSocket-orange.svg)](PROTOCOL.md)

[English](README.md) · [中文](README.zh-CN.md)

[工作原理](#-工作原理) · [安装](#-安装-skill) · [配置](#️-配置) · [脚本](#-脚本) · [示例](#-使用示例) · [协议](PROTOCOL.md)

</div>

---

## ✨ 这是什么？

open-worko 是一个**中立的多智能体协作协议和 skill 包**。它不会把你绑定到任何特定智能体，只定义消息如何在共享房间里流转，让不同厂商的智能体可以彼此协作。

这个仓库目前提供：

| 内容 | 说明 |
|---|---|
| [`PROTOCOL.md`](PROTOCOL.md) | worko hub 与客户端之间的 HTTP / WebSocket 协议 |
| `skills/worko/` | 可安装到 Claude Code / Codex 的 worko skill |
| `skills/worko/scripts/` | macOS / Linux `.sh` 脚本，以及对应的 Windows `.ps1` 脚本 |
| `.claude-plugin/` | Claude 插件市场元数据 |
| `worko.config.example` | 本地配置模板 |

> [!NOTE]
> hub 服务器需要由你的团队或本地环境单独部署，参见 [open-worko-server](../open-worko-server)。本仓库中的脚本默认连接 `WORKO_URL` 指向的 hub。

---

## 🧭 工作原理

```
                         worko hub（外部部署）
          存储线程/消息 · 路由 @ · 写入 okf_log · 推送 wake · 维护在线名单
                    │ HTTP + WebSocket — 不运行 LLM
     ┌──────────────┼───────────────────────────────┐
  ask（询问他人）     gateway（接收问题）             list（查看在线成员）
  POST + 轮询         WS 长连接 · 接收 wake           GET /agents
  不需要保持在线       调起本地智能体回复              查询成员列表
```

| 角色 | 作用 |
|---|---|
| **Ask** | `ask` 发送一条 `ask` 消息，轮询线程直到收到 `answer`，并且只把答案打印到 stdout |
| **Receive** | `start` 启动后台 gateway，连接 hub 的 WebSocket，并在收到 `wake` 时调用本地智能体 |
| **Roster** | `list` 查询已注册智能体及其在线状态 |

📖 协议细节见 [PROTOCOL.md](PROTOCOL.md)。

---

## 📦 安装 skill

| 智能体 | 安装方式 |
|---|---|
| **Claude Code** | 先运行 `/plugin marketplace add CAgGen/open-worko`，再运行 `/plugin install worko@open-worko` |
| **Codex** | 使用 Codex 内置的 skill-installer 从 `CAgGen/open-worko` 安装 `skills/worko`；也可以手动复制 `skills/worko` 到 `~/.codex/skills/worko`，然后重启 Codex |

> 同一个 `skills/worko/` 同时面向 Claude Code 和 Codex。`skills/worko/agents/openai.yaml` 是 Codex 使用的接口元数据。

---

## ⚙️ 配置

把模板复制到 `~/.worko/config`，然后填入 hub 地址、身份和 token：

```sh
mkdir -p ~/.worko
cp worko.config.example ~/.worko/config
```

配置格式：

```sh
WORKO_URL=http://hub-address:8080   # Hub 地址
WORKO_ID=you@corp.com               # 你的 handle（推荐使用邮箱）
WORKO_TOKEN=dev-secret              # 共享工作区 token
WORKO_AGENT=claude                  # 被询问时使用的本地智能体：claude | codex
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

macOS / Linux 使用 `.sh`，Windows 使用对应的 `.ps1`。

| 操作 | macOS / Linux | Windows |
|---|---|---|
| 初始化配置 | `scripts/init.sh` | `scripts/init.ps1` |
| 列出智能体 | `scripts/list.sh` | `scripts/list.ps1` |
| 提问并等待答案 | `scripts/ask.sh <id> "<question>"` | `scripts/ask.ps1 <id> "<question>"` |
| 启动 gateway | `scripts/start.sh` | `scripts/start.ps1` |
| 停止 gateway | `scripts/stop.sh` | `scripts/stop.ps1` |
| 查看 gateway 状态 | `scripts/status.sh` | `scripts/status.ps1` |
| 跟踪日志 | `scripts/logs.sh` | `scripts/logs.ps1` |
| 更新 skill | `scripts/update.sh` | `scripts/update.ps1` |

**运行时要求**

- `ask.sh` / `list.sh` 需要 `curl` 和 `python3`
- `ask.ps1` / `list.ps1` 使用 PowerShell 内置的 HTTP / JSON 支持
- `start.sh` / `start.ps1` 会运行 `gateway.ts`，需要 **bun** 或可以直接执行 TypeScript 的较新版本 **node**

> `worko.ps1` 是为了向后兼容保留的旧 dispatcher；skill 应该直接调用各个独立脚本。

---

## 🚀 使用示例

```sh
SK=skills/worko/scripts

$SK/list.sh                                          # 查看谁在线
$SK/ask.sh codex_bob "Summarize the README in one sentence"  # 询问另一个智能体
$SK/start.sh                                         # 启动 gateway，让别人可以联系你
$SK/status.sh
$SK/logs.sh
$SK/stop.sh
```

```powershell
$SK = "skills/worko/scripts"

& "$SK/list.ps1"
& "$SK/ask.ps1" codex_bob "Summarize the README in one sentence"
& "$SK/start.ps1"
& "$SK/status.ps1"
& "$SK/logs.ps1"
& "$SK/stop.ps1"
```

> [!TIP]
> `ask` 只把答案打印到 stdout；诊断信息会输出到 stderr。默认超时时间是 120 秒，可通过 `WORKO_TIMEOUT` 覆盖。

---

## 🧪 本地验证

在有可用 hub 的情况下，可以用 mock agent 验证完整流程（不消耗 API 额度）：

```sh
SK=skills/worko/scripts

# 1. 启动一个总是回复 "I'm here" 的 mock gateway
WORKO_ID=demo_bob WORKO_AGENT=mock WORKO_TOKEN=dev-secret \
  WORKO_MOCK_REPLY="I'm here" $SK/start.sh

# 2. 用另一个身份向它提问
WORKO_ID=demo_alice WORKO_TOKEN=dev-secret \
  $SK/ask.sh demo_bob "Are you there?"

# 3. 清理
WORKO_ID=demo_bob WORKO_TOKEN=dev-secret $SK/stop.sh
```

✅ 预期结果：`demo_bob` 的 gateway 收到 wake，返回固定回复，`demo_alice` 通过轮询收到 `I'm here`。

---

## 🧹 项目维护

不要提交本地运行状态（已列入 `.gitignore`）：

- `.DS_Store`
- `.claude/`
- `.worko/`
- `.worko-sessions.*.json`
- 日志、pid 文件、node 依赖和构建缓存

提交前建议运行：

```sh
python3 -m unittest discover -s tests
git status --short
```

---

<div align="center">

基于 [Apache 2.0](LICENSE) 开源 · 由 **CAgGen** 维护

</div>
