#!/usr/bin/env bash
# worko start —— 后台起 gateway daemon（让别人能喊到你）。不挡当前 shell。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${WORKO_CONFIG:-$HOME/.worko/config}"; [ -f "$CONFIG" ] && . "$CONFIG"

# 没配置且没传 env → 引导初始化：人手跑自动进交互，agent 无 TTY 则提示先 init。
if [ ! -f "$CONFIG" ] && [ -z "${WORKO_ID:-}" ]; then
  if [ -t 0 ]; then
    echo "[worko] 没找到 $CONFIG，先配置一下："
    "$HERE/init.sh" || exit 1
    . "$CONFIG"
  else
    echo "[worko] 没有 $CONFIG。先跑 init.sh 配置，或传 WORKO_ID/WORKO_TOKEN 等环境变量。" >&2
    echo "        （agent：先问用户拿 hub地址/id/token，再 init.sh --url U --id I --token T --agent codex）" >&2
    exit 1
  fi
fi

ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "需要 WORKO_ID（在 $CONFIG 或环境变量里设）" >&2; exit 1; }
GW="$HERE/gateway.ts"
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; mkdir -p "$RUN"
PID="$RUN/$ID.pid"; LOG="$RUN/$ID.log"

# 运行时：优先 bun（项目本家、原生跑 .ts），没有就退回 node（v22.6+ 能擦类型跑 .ts）。
RT="${WORKO_RUNTIME:-}"
if [ -z "$RT" ]; then
  if command -v bun >/dev/null 2>&1; then RT=bun
  elif command -v node >/dev/null 2>&1; then RT=node
  else echo "需要 bun 或 node（任一）来跑 gateway" >&2; exit 1; fi
fi

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "[worko] daemon 已在跑 pid=$(cat "$PID")"; exit 0
fi
HUB="${WORKO_URL:-http://localhost:8080}"
curl -fsS -m 3 "$HUB/health" >/dev/null 2>&1 || echo "[worko] 警告：$HUB 暂时连不上，daemon 会自动重连"
nohup "$RT" "$GW" >"$LOG" 2>&1 &
echo $! > "$PID"
echo "[worko] gateway 起好 pid=$(cat "$PID")  id=$ID  agent=${WORKO_AGENT:-claude}  runtime=$RT  log=$LOG"
