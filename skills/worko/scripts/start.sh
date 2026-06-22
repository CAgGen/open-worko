#!/usr/bin/env bash
# worko start — launch the gateway daemon in the background (so others can reach you). Non-blocking.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_config.sh"

# No config and no env vars → guide initialization: interactive if TTY, otherwise prompt to run init first.
if [ ! -f "$CONFIG" ] && [ -z "${WORKO_ID:-}" ]; then
  if [ -t 0 ]; then
    echo "[worko] Config not found at $CONFIG, setting up now:"
    "$HERE/init.sh" || exit 1
    . "$CONFIG"
  else
    echo "[worko] No config at $CONFIG. Run init.sh first, or set WORKO_ID/WORKO_TOKEN etc. as environment variables." >&2
    echo "        (agent: ask the user for hub address/id/token, then run: init.sh --url U --id I --token T --agent codex)" >&2
    exit 1
  fi
fi

ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "WORKO_ID is required (set in $CONFIG or as an environment variable)" >&2; exit 1; }
GW="$HERE/gateway.ts"
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; mkdir -p "$RUN"
PID="$RUN/$ID.pid"; LOG="$RUN/$ID.log"

# Runtime: prefer bun (native .ts support), fall back to node (v22.6+ can run .ts without compilation).
RT="${WORKO_RUNTIME:-}"
if [ -z "$RT" ]; then
  if command -v bun >/dev/null 2>&1; then RT=bun
  elif command -v node >/dev/null 2>&1; then RT=node
  else echo "bun or node is required to run the gateway" >&2; exit 1; fi
fi

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "[worko] daemon already running pid=$(cat "$PID")"; exit 0
fi
HUB="${WORKO_URL:-http://localhost:8080}"
curl -fsS -m 3 "$HUB/health" >/dev/null 2>&1 || echo "[worko] Warning: $HUB is unreachable — daemon will retry automatically"
nohup "$RT" "$GW" >"$LOG" 2>&1 &
echo $! > "$PID"
echo "[worko] gateway started pid=$(cat "$PID")  id=$ID  agent=${WORKO_AGENT:-claude}  runtime=$RT  log=$LOG"
