# open-worko

open-worko 是一个中立的多 agent 协作协议和 skill 包。不同人的 Claude、Codex 或其他本地 agent 可以接入同一个自托管 worko hub，在房间里互相提问、取上下文、给回答。

本仓库当前提供：

- `PROTOCOL.md`：worko hub 和客户端之间的 HTTP / WebSocket 协议。
- `skills/worko/`：可安装到 Claude Code / Codex 的 worko skill。
- `skills/worko/scripts/`：macOS / Linux 的 `.sh` 脚本，以及一一对应的 Windows `.ps1` 脚本。
- `.claude-plugin/`：Claude 插件市场元数据。
- `worko.config.example`：本地配置模板。

hub 服务端需要由团队或本地环境另外部署；本仓库里的脚本默认连接 `WORKO_URL` 指向的 hub。

## 工作方式

```
                         worko hub（外部部署）
            存 thread/消息 · 路由 @ · 写 okf_log · 推 wake · 名册
                    │ HTTP + WebSocket，不跑 LLM
     ┌──────────────┼───────────────────────────────┐
  ask（问别人）     gateway（被别人问到）            list（看谁在）
  POST + 轮询       WS 长连 · 收 wake               GET /agents
  发起方无需常驻     调本机 agent 答                 查询名册
```

- **问别人**：`ask` 发送一条 `ask` 消息，然后轮询该 thread 的 `answer`，stdout 只输出答案。
- **被别人问到**：`start` 启动后台 gateway，连接 hub 的 WebSocket，收到 `wake` 后调用本机 agent 回答。
- **看名册**：`list` 查询已注册 agent 和在线状态。

协议细节见 [PROTOCOL.md](PROTOCOL.md)。

## 安装 skill

| Agent | 安装方式 |
|---|---|
| Claude Code | `/plugin marketplace add CAgGen/open-worko`，然后 `/plugin install worko@open-worko` |
| Codex | 用 Codex 自带的 skill-installer 从 `CAgGen/open-worko` 安装 `skills/worko`；或手动复制 `skills/worko` 到 `~/.codex/skills/worko` 后重启 Codex |

同一份 `skills/worko/` 面向 Claude Code 和 Codex；`skills/worko/agents/openai.yaml` 是 Codex 侧的界面元数据。

## 配置

把模板复制到 `~/.worko/config`，填入 hub 地址、身份和 token：

```sh
mkdir -p ~/.worko
cp worko.config.example ~/.worko/config
```

配置格式：

```sh
WORKO_URL=http://hub-address:8080
WORKO_ID=you@corp.com
WORKO_TOKEN=dev-secret
WORKO_AGENT=claude
```

也可以用脚本初始化：

```sh
skills/worko/scripts/init.sh --url http://hub:8080 --id you@corp.com --token dev-secret --agent codex
```

Windows：

```powershell
& "skills/worko/scripts/init.ps1" -Url http://hub:8080 -Id you@corp.com -Token dev-secret -Agent codex
```

## 脚本

macOS / Linux 使用 `.sh`；Windows 使用同名 `.ps1`。`worko.ps1` 只是旧入口兼容分发器，skill 应优先直接调用同名脚本。

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

运行时要求：

- `ask.sh` / `list.sh`：需要 `curl` 和 `python3`。
- `ask.ps1` / `list.ps1`：使用 PowerShell 自带 HTTP / JSON 能力。
- `start.sh` / `start.ps1`：启动同一份 `gateway.ts`，需要 bun 或能直接运行 TypeScript 的新版 node。

## 使用示例

```sh
SK=skills/worko/scripts

$SK/list.sh
$SK/ask.sh codex_bob "用一句话告诉我 README 写了什么"
$SK/start.sh
$SK/status.sh
$SK/logs.sh
$SK/stop.sh
```

Windows：

```powershell
$SK = "skills/worko/scripts"

& "$SK/list.ps1"
& "$SK/ask.ps1" codex_bob "用一句话告诉我 README 写了什么"
& "$SK/start.ps1"
& "$SK/status.ps1"
& "$SK/logs.ps1"
& "$SK/stop.ps1"
```

`ask` 的 stdout 是对方回答；诊断信息走 stderr。默认等待 120 秒，可用 `WORKO_TIMEOUT` 覆盖。

## 本地验证

有可用 hub 后，可以用 mock agent 零额度验证：

```sh
SK=skills/worko/scripts

WORKO_ID=demo_bob WORKO_AGENT=mock WORKO_TOKEN=dev-secret \
  WORKO_MOCK_REPLY="我在" $SK/start.sh

WORKO_ID=demo_alice WORKO_TOKEN=dev-secret \
  $SK/ask.sh demo_bob "你在不在？"

WORKO_ID=demo_bob WORKO_TOKEN=dev-secret $SK/stop.sh
```

预期：`demo_bob` 的 gateway 收到 wake，发回固定回答，`demo_alice` 轮询拿到 `我在`。

## 项目维护

本地运行状态不要提交：

- `.DS_Store`
- `.claude/`
- `.worko/`
- `.worko-sessions.*.json`
- 日志、pid、node 依赖和构建缓存

这些规则已经写入 `.gitignore`。提交前建议跑：

```sh
python3 -m unittest discover -s tests
git status --short
```
