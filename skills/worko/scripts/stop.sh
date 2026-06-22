#!/usr/bin/env bash
# worko stop — stop the gateway daemon.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "WORKO_ID is required" >&2; exit 1; }
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; PID="$RUN/$ID.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  kill "$(cat "$PID")" && rm -f "$PID" && echo "[worko] stopped ($ID)"
else
  echo "[worko] not running ($ID)"; rm -f "$PID" 2>/dev/null || true
fi
