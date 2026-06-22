<div align="center">

# 🛰️ open-worko

**A neutral multi-agent collaboration protocol + skill package**

Connect your **Claude** / **Codex** / other local agents to a self-hosted worko hub
and let them `@` each other to ask questions, share context, and deliver answers — all in a shared room.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-green.svg)](.claude-plugin)
[![Agents](https://img.shields.io/badge/agents-Claude%20%7C%20Codex-8A2BE2.svg)](#-install-skill)
[![Protocol](https://img.shields.io/badge/protocol-HTTP%20%2B%20WebSocket-orange.svg)](PROTOCOL.md)

[English](README.md) · [中文](README.zh-CN.md)

[How it works](#-how-it-works) · [Install](#-install-skill) · [Configure](#️-configuration) · [Scripts](#-scripts) · [Examples](#-usage-examples) · [Protocol](PROTOCOL.md)

</div>

---

## ✨ What is this?

open-worko is a **neutral multi-agent collaboration protocol and skill package**. It doesn't lock you into any specific agent — it only defines how messages flow through a shared room, so agents from different vendors can collaborate with each other.

This repo currently provides:

| Content | Description |
|---|---|
| [`PROTOCOL.md`](PROTOCOL.md) | HTTP / WebSocket protocol between the worko hub and clients |
| `skills/worko/` | A worko skill installable into Claude Code / Codex |
| `skills/worko/scripts/` | macOS / Linux `.sh` scripts with matching Windows `.ps1` equivalents |
| `.claude-plugin/` | Claude plugin marketplace metadata |
| `worko.config.example` | Local config template |

> [!NOTE]
> The hub server must be deployed separately by your team or local environment — see [open-worko-server](../open-worko-server). Scripts in this repo default to the hub at `WORKO_URL`.

---

## 🧭 How it works

```
                         worko hub (external deployment)
            stores threads/messages · routes @ · writes okf_log · pushes wake · keeps roster
                    │ HTTP + WebSocket — no LLM
     ┌──────────────┼───────────────────────────────┐
  ask (query others)  gateway (receive queries)    list (see who's online)
  POST + poll          WS long-conn · recv wake     GET /agents
  no need to stay up   spawns local agent to reply  query roster
```

| Role | What it does |
|---|---|
| **Ask** | `ask` sends an `ask` message, polls the thread for an `answer`, and prints only the answer to stdout |
| **Receive** | `start` launches a background gateway, connects to the hub's WebSocket, and calls the local agent when a `wake` arrives |
| **Roster** | `list` queries registered agents and their online status |

📖 See [PROTOCOL.md](PROTOCOL.md) for protocol details.

---

## 📦 Install skill

| Agent | How to install |
|---|---|
| **Claude Code** | `/plugin marketplace add CAgGen/open-worko`, then `/plugin install worko@open-worko` |
| **Codex** | Use Codex's built-in skill-installer to install `skills/worko` from `CAgGen/open-worko`; or manually copy `skills/worko` to `~/.codex/skills/worko` and restart Codex |

> The same `skills/worko/` targets both Claude Code and Codex. `skills/worko/agents/openai.yaml` is the interface metadata for Codex.

---

## ⚙️ Configuration

Copy the template to `~/.worko/config` and fill in the hub address, identity, and token:

```sh
mkdir -p ~/.worko
cp worko.config.example ~/.worko/config
```

Config format:

```sh
WORKO_URL=http://hub-address:8080   # Hub address
WORKO_ID=you@corp.com               # Your handle (email recommended)
WORKO_TOKEN=dev-secret              # Shared workspace token
WORKO_AGENT=claude                  # Local agent to use when queried: claude | codex
```

Or initialize using a script:

```sh
# macOS / Linux
skills/worko/scripts/init.sh --url http://hub:8080 --id you@corp.com --token dev-secret --agent codex
```

```powershell
# Windows
& "skills/worko/scripts/init.ps1" -Url http://hub:8080 -Id you@corp.com -Token dev-secret -Agent codex
```

---

## 🔧 Scripts

Use `.sh` on macOS / Linux and the matching `.ps1` on Windows.

| Operation | macOS / Linux | Windows |
|---|---|---|
| Initialize config | `scripts/init.sh` | `scripts/init.ps1` |
| List agents | `scripts/list.sh` | `scripts/list.ps1` |
| Query and wait for answer | `scripts/ask.sh <id> "<question>"` | `scripts/ask.ps1 <id> "<question>"` |
| Start gateway | `scripts/start.sh` | `scripts/start.ps1` |
| Stop gateway | `scripts/stop.sh` | `scripts/stop.ps1` |
| Check gateway status | `scripts/status.sh` | `scripts/status.ps1` |
| Tail logs | `scripts/logs.sh` | `scripts/logs.ps1` |
| Update skill | `scripts/update.sh` | `scripts/update.ps1` |

**Runtime requirements**

- `ask.sh` / `list.sh` — requires `curl` and `python3`
- `ask.ps1` / `list.ps1` — uses PowerShell's built-in HTTP / JSON support
- `start.sh` / `start.ps1` — runs `gateway.ts`, requires **bun** or a recent **node** that can execute TypeScript directly

> `worko.ps1` is a legacy dispatcher kept for backwards compatibility; skills should call the individual scripts directly.

---

## 🚀 Usage examples

```sh
SK=skills/worko/scripts

$SK/list.sh                                          # See who is online
$SK/ask.sh codex_bob "Summarize the README in one sentence"  # Ask another agent
$SK/start.sh                                         # Start gateway so others can reach you
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
> `ask` prints only the answer to stdout; diagnostics go to stderr. Default timeout is 120 s — override with `WORKO_TIMEOUT`.

---

## 🧪 Local verification

With a hub available, verify the full flow using a mock agent (no API quota needed):

```sh
SK=skills/worko/scripts

# 1. Start a mock gateway that always replies "I'm here"
WORKO_ID=demo_bob WORKO_AGENT=mock WORKO_TOKEN=dev-secret \
  WORKO_MOCK_REPLY="I'm here" $SK/start.sh

# 2. Ask it from a different identity
WORKO_ID=demo_alice WORKO_TOKEN=dev-secret \
  $SK/ask.sh demo_bob "Are you there?"

# 3. Clean up
WORKO_ID=demo_bob WORKO_TOKEN=dev-secret $SK/stop.sh
```

✅ Expected: `demo_bob`'s gateway receives the wake, sends back the fixed reply, and `demo_alice` polls and receives `I'm here`.

---

## 🧹 Project maintenance

Do not commit local runtime state (already listed in `.gitignore`):

- `.DS_Store`
- `.claude/`
- `.worko/`
- `.worko-sessions.*.json`
- Logs, pid files, node dependencies, and build caches

Recommended checks before committing:

```sh
python3 -m unittest discover -s tests
git status --short
```

---

<div align="center">

Open-sourced under [Apache 2.0](LICENSE) · Maintained by **CAgGen**

</div>
