#!/usr/bin/env bash
# worko ask <对方id> <问题> —— 发问并等回答。纯 curl，不需要 node。
# 答案打到 stdout，诊断打到 stderr。默认 120s 超时（WORKO_TIMEOUT 可调）。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
HUB="${WORKO_URL:-http://localhost:8080}"; ID="${WORKO_ID:-}"; TOKEN="${WORKO_TOKEN:-}"
# ROOM 留空：服务器按 token 自动定位本 workspace 的 room。乱填 room_dev 会被 403。
ROOM="${WORKO_ROOM:-}"; TIMEOUT="${WORKO_TIMEOUT:-120}"

to="${1:-}"; shift || true; q="${*:-}"
[ -n "$ID" ] && [ -n "$to" ] && [ -n "$q" ] || { echo "用法: WORKO_ID=你 ask.sh <对方id> <问题>" >&2; exit 1; }
auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")

# 发问 → 拿 thread
body=$(python3 -c 'import json,sys
m={"from":sys.argv[2],"to":[sys.argv[3]],"type":"ask","content":sys.argv[4]}
if sys.argv[1]: m["room"]=sys.argv[1]
print(json.dumps(m))' "$ROOM" "$ID" "$to" "$q")
thread=$(curl -fsS "${auth[@]}" -H 'content-type: application/json' -d "$body" "$HUB/messages" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["thread"])')
echo "[$ID] 已问 $to (thread=$thread)，等回答…" >&2

# 轮询 /context 找发给我的 answer
end=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 1
  ans=$(curl -fsS "${auth[@]}" "$HUB/context?thread=$thread" | python3 -c '
import json,sys
me=sys.argv[1]; d=json.load(sys.stdin)
for m in d.get("recent",[]):
    if m.get("type")=="answer" and me in (m.get("to") or []):
        sys.stdout.write(m.get("content","")); break
' "$ID")
  if [ -n "$ans" ]; then printf '%s\n' "$ans"; exit 0; fi
done
echo "[$ID] 等 $to 超时(${TIMEOUT}s)" >&2; exit 1
