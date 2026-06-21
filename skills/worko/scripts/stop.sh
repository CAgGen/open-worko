#!/usr/bin/env bash
# worko stop —— 停掉 gateway daemon。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "需要 WORKO_ID" >&2; exit 1; }
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; PID="$RUN/$ID.pid"
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  kill "$(cat "$PID")" && rm -f "$PID" && echo "[worko] 已停止 ($ID)"
else
  echo "[worko] 没在跑 ($ID)"; rm -f "$PID" 2>/dev/null || true
fi
