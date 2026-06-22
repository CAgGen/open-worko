#!/usr/bin/env bash
# worko ask <target-id> <question> — send a question and wait for the answer. Uses only curl, no node.
# Answer goes to stdout; diagnostics go to stderr. Default timeout: 120 s (override with WORKO_TIMEOUT).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
HUB="${WORKO_URL:-http://localhost:8080}"; ID="${WORKO_ID:-}"; TOKEN="${WORKO_TOKEN:-}"
# ROOM left empty: server automatically locates the workspace room via token. Setting it to room_dev causes 403.
ROOM="${WORKO_ROOM:-}"; TIMEOUT="${WORKO_TIMEOUT:-120}"

to="${1:-}"; shift || true; q="${*:-}"
[ -n "$ID" ] && [ -n "$to" ] && [ -n "$q" ] || { echo "Usage: WORKO_ID=you ask.sh <target-id> <question>" >&2; exit 1; }
auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")

# Send question → get thread id
body=$(python3 -c 'import json,sys
m={"from":sys.argv[2],"to":[sys.argv[3]],"type":"ask","content":sys.argv[4]}
if sys.argv[1]: m["room"]=sys.argv[1]
print(json.dumps(m))' "$ROOM" "$ID" "$to" "$q")
thread=$(curl -fsS "${auth[@]}" -H 'content-type: application/json' -d "$body" "$HUB/messages" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["thread"])')
echo "[$ID] Sent to $to (thread=$thread), waiting for answer..." >&2

# Poll /context for an answer addressed to me
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
echo "[$ID] Timed out waiting for $to (${TIMEOUT}s)" >&2; exit 1
