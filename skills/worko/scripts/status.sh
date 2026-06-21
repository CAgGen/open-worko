#!/usr/bin/env bash
# worko status —— 看 gateway daemon 在不在。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "需要 WORKO_ID" >&2; exit 1; }
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; PID="$RUN/$ID.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "[worko] running  pid=$(cat "$PID")  id=$ID  url=${WORKO_URL:-http://localhost:8080}"
else
  echo "[worko] stopped  id=$ID"
fi
