#!/usr/bin/env bash
# worko init — write ~/.worko/config.
# Two usage modes:
#   Human (run in terminal): prompts interactively for any missing values.   init.sh
#   Agent (no TTY): pass all values as arguments.                            init.sh --url U --id I --token T --agent codex
set -euo pipefail
# Write destination: WORKO_CONFIG takes priority; otherwise project-level ./.worko/config (one per project).
# For machine-level shared config: WORKO_CONFIG=$HOME/.worko/config init.sh ...
CONFIG="${WORKO_CONFIG:-$PWD/.worko/config}"

URL="${WORKO_URL:-}"; ID="${WORKO_ID:-}"; TOKEN="${WORKO_TOKEN:-}"; AGENT="${WORKO_AGENT:-}"; ROOM="${WORKO_ROOM:-}"
# Working directory for the local agent: defaults to current directory.
# The gateway uses this as cwd + sandbox boundary — the agent can only operate within this directory.
WORKO_AGENT_CWD="${WORKO_AGENT_CWD:-$PWD}"
while [ $# -gt 0 ]; do
  case "$1" in
    --url)   URL="$2";   shift 2;;
    --id)    ID="$2";    shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --agent) AGENT="$2"; shift 2;;
    -h|--help) echo "Usage: init.sh [--url U] [--id I] [--token T] [--agent claude|codex]"; exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 1;;
  esac
done

# For missing fields: prompt interactively if there is a TTY (human); leave empty if no TTY (agent) and validate below.
ask() {  # ask VARNAME "prompt" "default"
  local var="$1" q="$2" def="$3" ans
  [ -n "${!var}" ] && return
  if [ -t 0 ]; then
    read -r -p "$q${def:+ [$def]}: " ans
    printf -v "$var" '%s' "${ans:-$def}"
  fi
}
ask URL   "Hub address (WORKO_URL)"                    "http://localhost:8080"
ask ID    "Your identity/email (WORKO_ID)"              ""
ask TOKEN "Workspace token (WORKO_TOKEN)"               ""
ask AGENT "Local agent (WORKO_AGENT: claude|codex)"    "claude"

# Validate required fields
err=()
[ -n "$URL" ] || err+=("--url")
[ -n "$ID" ]  || err+=("--id")
if [ ${#err[@]} -gt 0 ]; then
  echo "[worko] Missing required fields: ${err[*]}" >&2
  echo "        For non-interactive use, pass as arguments, e.g.:" >&2
  echo "        init.sh --url http://hub:8080 --id you@corp.com --token <token> --agent codex" >&2
  exit 1
fi

URL="${URL%/}"  # strip trailing slash to avoid double-slash in $URL/agents

# Fetch room id from the hub using the token when joining a workspace:
#  1) Subsequent messages include the correct room, avoiding "room not in workspace" 403s.
#  2) Also validates the token/connection — failure is surfaced now rather than on the first ask.
# If unavailable (offline / wrong token), leave empty: server falls back to token-based room resolution.
if [ -z "$ROOM" ] && command -v python3 >/dev/null 2>&1; then
  auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")
  # Only use the result when /rooms returns exactly 1 room:
  #  - authed mode: token locks the result to your workspace — always 1 → safe to use.
  #  - dev mode (no ADMIN_TOKEN): /rooms returns all workspace rooms — can't tell which one is yours → skip.
  ROOM=$(curl -fsS -m 5 "${auth[@]}" "$URL/rooms" 2>/dev/null | python3 -c '
import json,sys
try:
    r = json.load(sys.stdin).get("rooms") or []
    print(r[0]["id"] if len(r) == 1 else "")
except Exception: pass' 2>/dev/null) || ROOM=""
  [ -n "$ROOM" ] || echo "[worko] Note: could not determine a unique room (unreachable / wrong token / dev mode with multiple workspaces). Leaving empty — server will resolve via token at send time." >&2
fi

umask 077
mkdir -p "$(dirname "$CONFIG")"
# export so that child processes spawned after sourcing start.sh also get these variables.
cat > "$CONFIG" <<EOF
export WORKO_URL=$URL
export WORKO_ID=$ID
export WORKO_TOKEN=$TOKEN
export WORKO_AGENT=$AGENT
export WORKO_AGENT_CWD=$WORKO_AGENT_CWD
${ROOM:+export WORKO_ROOM=$ROOM}
EOF
echo "[worko] Written to $CONFIG"
echo "        id=$ID  url=$URL  agent=$AGENT  token=${TOKEN:+set}  room=${ROOM:-not fetched (resolved at runtime)}  workdir=$WORKO_AGENT_CWD"
