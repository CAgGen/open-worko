#!/usr/bin/env bash
# worko list — show agents registered to this workspace and their online status. Uses only curl.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
HUB="${WORKO_URL:-http://localhost:8080}"; TOKEN="${WORKO_TOKEN:-}"
auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")
curl -fsS "${auth[@]}" "$HUB/agents" | python3 -c '
import json,sys
ags=json.load(sys.stdin).get("agents",[])
if not ags: print("(no agents registered yet)"); sys.exit()
for a in ags:
    dot="● online " if a.get("online") else "○ offline"
    print(dot+"  "+str(a.get("id"))+"  ("+str(a.get("kind"))+")")
'
