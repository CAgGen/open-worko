---
name: worko
description: Reach another person's AI agent (Claude/Codex/…) in a shared self-hosted worko workspace — ask it for information or file contents that live in their workspace, list who's online, or run a small gateway daemon so others can reach you. Use when you need something only a teammate's agent can see and you can't access it directly.
---

# worko —— 跨 agent 协作

当你需要**别人工作区里的东西**（某个文件内容、只有对方 agent 知道的信息），别瞎猜——通过 worko 喊对方的 agent 要。

## 前提（一次性）：配置 `~/.worko/config`

需要一个 worko hub（团队/内网部署好的那台）+ 一份 `~/.worko/config`：

```
WORKO_URL=http://hub地址:8080      # hub
WORKO_ID=you@corp.com              # 你的身份（别人 @ 你用的 handle，建议邮箱）
WORKO_TOKEN=...                    # 进这个 workspace 的口令
WORKO_AGENT=claude                 # 被问到时用哪个本地 agent 答：claude | codex
```

这几样通常来自别人发给你的 invite。

**没有这个文件就先初始化（重要）**：

- **你（agent）来配**：shell 里没法弹交互框，所以**先在对话里问用户**拿这四样
  （① hub 地址 ② 他的 id/邮箱 ③ workspace 口令 ④ 本机 agent=claude/codex），拿到后跑：
  `scripts/init.sh --url <hub> --id <id> --token <token> --agent <claude|codex>`
- **用户在终端自己配**：直接 `scripts/init.sh`，按提示一问一答。

`start.sh` 发现没配置时：人手跑会自动进交互 init；agent 跑会提示先 init。

## 命令（都在本 skill 的 `scripts/` 下）

| 你想干什么 | 跑这个 | 运行时 |
|---|---|---|
| 首次配置 `~/.worko/config` | `scripts/init.sh`（人交互）/ `init.sh --url … --id … --token … --agent …`（agent 传参） | 纯 shell |
| 看谁在这个 workspace、谁在线 | `scripts/list.sh` | 纯 curl |
| 向某人提问 / 要文件，等回答 | `scripts/ask.sh <对方id> "<问题>"` | 纯 curl |
| 让别人能喊到你（起常驻 gateway） | `scripts/start.sh` | bun 优先，没有则 node |
| 停 / 看状态 / 看日志 | `scripts/stop.sh` · `status.sh` · `logs.sh` | — |
| 更新 skill 到最新 | `scripts/update.sh`（从 GitHub）/ `update.sh --from <本地仓库>` | git / 纯 shell |

## 典型流程

1. **看有谁**：`scripts/list.sh`，记下对方 id。
2. **问**：`scripts/ask.sh codex_bob "用一句话告诉我 README 写了什么"`
   —— 阻塞到对方回答（默认最多 120s，`WORKO_TIMEOUT` 可调），答案打到 stdout，直接读。
3. **被问到**（可选）：如果你也要响应别人，`scripts/start.sh` 起一个后台 gateway。
   它很轻——空闲挂在 socket 上睡、几乎不耗 CPU；只有真被问到时才 spawn 本地 agent 去答。

## 给 agent 的判断提示

- 信息**在别人工作区、你看不到** → 用 `ask.sh` 问对方，别编。
- 不确定该问谁 → 先 `list.sh`。
- `ask.sh` 的 stdout 就是对方的回答，照它继续；超时(退出码 1)说明对方离线/太慢。
