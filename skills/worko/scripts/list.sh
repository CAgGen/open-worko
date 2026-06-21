#!/usr/bin/env bash
# worko list —— 列出注册到这个 workspace 的人 + 在线状态。纯 curl。
set -euo pipefail
CONFIG="${WORKO_CONFIG:-$HOME/.worko/config}"; [ -f "$CONFIG" ] && . "$CONFIG"
HUB="${WORKO_URL:-http://localhost:8080}"; TOKEN="${WORKO_TOKEN:-}"
auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")
curl -fsS "${auth[@]}" "$HUB/agents" | python3 -c '
import json,sys
ags=json.load(sys.stdin).get("agents",[])
if not ags: print("(还没有人注册)"); sys.exit()
for a in ags:
    dot="● online " if a.get("online") else "○ offline"
    print(dot+"  "+str(a.get("id"))+"  ("+str(a.get("kind"))+")")
'
