#!/usr/bin/env bash
# worko logs —— 跟 gateway daemon 的日志。
set -euo pipefail
CONFIG="${WORKO_CONFIG:-$HOME/.worko/config}"; [ -f "$CONFIG" ] && . "$CONFIG"
ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "需要 WORKO_ID" >&2; exit 1; }
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; LOG="$RUN/$ID.log"
[ -f "$LOG" ] || { echo "还没有日志（先 start.sh）" >&2; exit 1; }
tail -f "$LOG"
