---
name: worko
description: Reach another person's AI agent (Claude/Codex/…) in a shared self-hosted worko workspace — ask it for information or file contents that live in their workspace, list who's online, or run a small gateway daemon so others can reach you. Use when you need something only a teammate's agent can see and you can't access it directly.
---

# worko — cross-agent collaboration

When you need **something from another person's workspace** (a file's contents, information only their agent knows), don't guess — use worko to ask their agent directly.

## Prerequisite (one-time): set up config

You need a worko hub (deployed by your team on the internal network) plus a config file.

**Where config is looked up** (in priority order):
1. The path in the `WORKO_CONFIG` environment variable (highest priority)
2. The nearest `./.worko/config` walking up from the current directory (**project-level** — one per project, lets you join different workspaces)
3. `~/.worko/config` (machine-level fallback)

`init.sh` writes to **project-level** `./.worko/config` by default. For machine-level config: `WORKO_CONFIG=$HOME/.worko/config scripts/init.sh ...`.

Config is plain `KEY=VALUE` (not JSON):

```
WORKO_URL=http://hub-address:8080  # hub
WORKO_ID=you@corp.com              # your identity (handle others use to @ you — email recommended)
WORKO_TOKEN=...                    # shared token to access this workspace
WORKO_AGENT=claude                 # local agent to use when queried: claude | codex
```

`WORKO_ROOM` is not required — `init` fetches the workspace room id using your token and writes it to config automatically (also validates that the token and connection are working). If not fetched, it stays empty and the server resolves the room via token at send time.

These values typically come from an invite sent to you.

**No config yet? Initialize first (important)**:

- **Agent does it**: no interactive prompt is available in a shell, so **ask the user first** for the four values
  (① hub address ② their id/email ③ workspace token ④ local agent = claude/codex), then run:
  - macOS / Linux: `scripts/init.sh --url <hub> --id <id> --token <token> --agent <claude|codex>`
  - Windows: `scripts/init.ps1 -Url <hub> -Id <id> -Token <token> -Agent <claude|codex>`
- **User does it in the terminal**: macOS / Linux: `scripts/init.sh`; Windows: `scripts/init.ps1` — follow the interactive prompts.

`start.sh` / `start.ps1` detect missing config: when run by a human they launch interactive init automatically; when run by an agent they print a prompt to run init first.

**Note for users of codex as local agent**: the codex CLI refuses to execute in non-git / non-trusted directories by default (reports `Not inside a trusted directory…`, resulting in no output). The gateway hardcodes `--skip-git-repo-check` to bypass this check — it only skips the "is this a git repo" check, **it does not touch the sandbox** (sandbox remains read-only as usual). **No option to bypass the sandbox is exposed**: the gateway answers anyone in the workspace, so there must be no remote path to break out of the sandbox.

To let codex read files in a specific directory, set `WORKO_AGENT_CWD=<directory>` — the gateway spawns codex with that as the working directory (sandbox still read-only; safe).

If the agent produces no output, the reply will be `[codex no output exit=… | stderr: …]` — use the stderr to diagnose.

## Commands (all in `scripts/` of this skill)

**Pick scripts by OS first**: macOS / Linux → `scripts/*.sh`; Windows → matching `scripts/*.ps1`. `scripts/worko.ps1` is kept only as a legacy dispatcher; skills should call the individual scripts directly.

| What you want to do | macOS / Linux | Windows |
|---|---|---|
| First-time config | `scripts/init.sh` (interactive) / `scripts/init.sh --url … --id … --token … --agent …` (agent args) | `scripts/init.ps1` (interactive) / `scripts/init.ps1 -Url … -Id … -Token … -Agent …` |
| See who's in this workspace / who's online | `scripts/list.sh` | `scripts/list.ps1` |
| Ask someone a question / request a file, wait for answer | `scripts/ask.sh <their-id> "<question>"` | `scripts/ask.ps1 <their-id> "<question>"` |
| Let others reach you (start persistent gateway) | `scripts/start.sh` (bun preferred, falls back to node) | `scripts/start.ps1` (same — runs `gateway.ts`; requires node or bun on Windows) |
| Stop / check status | `scripts/stop.sh` · `scripts/status.sh` | `scripts/stop.ps1` · `scripts/status.ps1` |
| Follow logs | `scripts/logs.sh` | `scripts/logs.ps1` |
| Update skill to latest | `scripts/update.sh` (from GitHub) / `scripts/update.sh --from <local-repo>` | `scripts/update.ps1` (from GitHub) / `scripts/update.ps1 -From <local-repo>` |

## Typical flow

1. **See who's there**: `scripts/list.sh` (Windows: `scripts/list.ps1`) — note the other agent's id.
2. **Ask**: `scripts/ask.sh codex_bob "Summarize the README in one sentence"` (Windows: `scripts/ask.ps1 codex_bob "Summarize the README in one sentence"`)
   — blocks until the other agent replies (default max 120 s, adjustable via `WORKO_TIMEOUT`). Answer goes to stdout, read it directly.
3. **Receive queries** (optional): if you also want to respond to others, `scripts/start.sh` (Windows: `scripts/start.ps1`) starts a background gateway.
   It is lightweight — idles on a socket, almost no CPU; only spawns the local agent when actually queried.

## Hints for agents

- Information **is in someone else's workspace and you can't see it** → use `ask.sh` / `ask.ps1` to request it; don't fabricate.
- Not sure who to ask → run `list.sh` / `list.ps1` first.
- The stdout of `ask.sh` / `ask.ps1` is the other agent's answer — proceed from it; exit code 1 (timeout) means the other agent is offline or too slow.
