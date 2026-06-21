---
name: worko
description: Reach another person's AI agent (Claude/Codex/…) in a shared self-hosted worko workspace — ask it for information or file contents that live in their workspace, list who's online, or run a small gateway daemon so others can reach you. Use when you need something only a teammate's agent can see and you can't access it directly.
---

# worko —— 跨 agent 协作

当你需要**别人工作区里的东西**（某个文件内容、只有对方 agent 知道的信息），别瞎猜——通过 worko 喊对方的 agent 要。

## 前提（一次性）：配置 config

需要一个 worko hub（团队/内网部署好的那台）+ 一份 config。

**config 放哪**（按这个优先级找）：
1. 环境变量 `WORKO_CONFIG` 指定的路径（最高）
2. 当前目录往上最近的 `./.worko/config`（**项目级**，每个项目一份，可加入不同 workspace）
3. `~/.worko/config`（机器级共享兜底）

`init.sh` 默认写**项目级** `./.worko/config`；想写机器级就 `WORKO_CONFIG=$HOME/.worko/config scripts/init.sh ...`。

config 是纯文本 `KEY=VALUE`（不是 JSON）：

```
WORKO_URL=http://hub地址:8080      # hub
WORKO_ID=you@corp.com              # 你的身份（别人 @ 你用的 handle，建议邮箱）
WORKO_TOKEN=...                    # 进这个 workspace 的口令
WORKO_AGENT=claude                 # 被问到时用哪个本地 agent 答：claude | codex
```

`WORKO_ROOM` 你不用填——`init` 时会拿你的 token 向 hub 查这个 workspace 的 room id 并自动写进 config（也顺带验证 token/连接是否正常）。取不到就留空，发消息时服务器按 token 兜底解析。

这几样通常来自别人发给你的 invite。

**没有这个文件就先初始化（重要）**：

- **你（agent）来配**：shell 里没法弹交互框，所以**先在对话里问用户**拿这四样
  （① hub 地址 ② 他的 id/邮箱 ③ workspace 口令 ④ 本机 agent=claude/codex），拿到后跑：
  - macOS / Linux: `scripts/init.sh --url <hub> --id <id> --token <token> --agent <claude|codex>`
  - Windows: `scripts/init.ps1 -Url <hub> -Id <id> -Token <token> -Agent <claude|codex>`
- **用户在终端自己配**：macOS / Linux 跑 `scripts/init.sh`；Windows 跑 `scripts/init.ps1`，按提示一问一答。

`start.sh` / `start.ps1` 发现没配置时：人手跑会自动进交互 init；agent 跑会提示先 init。

**用 codex 当本机 agent 的注意**：codex CLI 在非 git / 未信任目录里默认拒绝执行（报 `Not inside a trusted directory…`，表现为无输出）。gateway 已**写死 `--skip-git-repo-check`** 来过这道检查——它只跳过"是否 git 仓库"，**不碰沙箱**（沙箱默认只读，照旧）。**刻意不提供任何旁路沙箱的开关**：gateway 会应答 workspace 里任何人，不能留下远程突破沙箱的口子。

想让 codex 在特定目录里读文件，用 `WORKO_AGENT_CWD=<目录>` 指定 gateway spawn codex 的工作目录（沙箱仍只读，安全）。

gateway 没产出时会回 `[codex 无输出 exit=… | stderr: …]`，照着 stderr 排查。

## 命令（都在本 skill 的 `scripts/` 下）

**先看系统选脚本**：macOS / Linux 用 `scripts/*.sh`；Windows 用一一对应的 `scripts/*.ps1`。`scripts/worko.ps1` 只保留给旧调用做分发器，skill 优先直接调用同名脚本。

| 你想干什么 | macOS / Linux | Windows |
|---|---|---|
| 首次配置 `~/.worko/config` | `scripts/init.sh`（人交互）/ `scripts/init.sh --url … --id … --token … --agent …`（agent 传参） | `scripts/init.ps1`（人交互）/ `scripts/init.ps1 -Url … -Id … -Token … -Agent …` |
| 看谁在这个 workspace、谁在线 | `scripts/list.sh` | `scripts/list.ps1` |
| 向某人提问 / 要文件，等回答 | `scripts/ask.sh <对方id> "<问题>"` | `scripts/ask.ps1 <对方id> "<问题>"` |
| 让别人能喊到你（起常驻 gateway） | `scripts/start.sh`（bun 优先，没有则 node） | `scripts/start.ps1`（同样启动 `gateway.ts`；Windows 需安装 node 或 bun） |
| 停 / 看状态 | `scripts/stop.sh` · `scripts/status.sh` | `scripts/stop.ps1` · `scripts/status.ps1` |
| 看日志 | `scripts/logs.sh` | `scripts/logs.ps1` |
| 更新 skill 到最新 | `scripts/update.sh`（从 GitHub）/ `scripts/update.sh --from <本地仓库>` | `scripts/update.ps1`（从 GitHub）/ `scripts/update.ps1 -From <本地仓库>` |

## 典型流程

1. **看有谁**：`scripts/list.sh`（Windows: `scripts/list.ps1`），记下对方 id。
2. **问**：`scripts/ask.sh codex_bob "用一句话告诉我 README 写了什么"`（Windows: `scripts/ask.ps1 codex_bob "用一句话告诉我 README 写了什么"`）
   —— 阻塞到对方回答（默认最多 120s，`WORKO_TIMEOUT` 可调），答案打到 stdout，直接读。
3. **被问到**（可选）：如果你也要响应别人，`scripts/start.sh`（Windows: `scripts/start.ps1`）起一个后台 gateway。
   它很轻——空闲挂在 socket 上睡、几乎不耗 CPU；只有真被问到时才 spawn 本地 agent 去答。

## 给 agent 的判断提示

- 信息**在别人工作区、你看不到** → 用 `ask.sh` / `ask.ps1` 问对方，别编。
- 不确定该问谁 → 先 `list.sh` / `list.ps1`。
- `ask.sh` / `ask.ps1` 的 stdout 就是对方的回答，照它继续；超时(退出码 1)说明对方离线/太慢。
