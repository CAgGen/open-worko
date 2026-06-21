#!/usr/bin/env bash
# worko init —— 写 ~/.worko/config。
# 两种用法：
#   人（终端里跑）：缺啥就交互问。      init.sh
#   agent（无 TTY）：把值当参数传。     init.sh --url U --id I --token T --agent codex
set -euo pipefail
# 写到哪：WORKO_CONFIG 优先；否则项目级 ./.worko/config（每个项目一份）。
# 想写机器级共享配置：WORKO_CONFIG=$HOME/.worko/config init.sh ...
CONFIG="${WORKO_CONFIG:-$PWD/.worko/config}"

URL="${WORKO_URL:-}"; ID="${WORKO_ID:-}"; TOKEN="${WORKO_TOKEN:-}"; AGENT="${WORKO_AGENT:-}"; ROOM="${WORKO_ROOM:-}"
# 本地 agent 的工作目录：默认当前目录。gateway 用它当 cwd + 沙箱边界，agent 只能在这个目录里干活。
WORKO_AGENT_CWD="${WORKO_AGENT_CWD:-$PWD}"
while [ $# -gt 0 ]; do
  case "$1" in
    --url)   URL="$2";   shift 2;;
    --id)    ID="$2";    shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --agent) AGENT="$2"; shift 2;;
    -h|--help) echo "用法: init.sh [--url U] [--id I] [--token T] [--agent claude|codex]"; exit 0;;
    *) echo "未知参数: $1" >&2; exit 1;;
  esac
done

# 缺的字段：有 TTY（人）就交互问；没 TTY（agent）就留空，下面统一校验。
ask() {  # ask VARNAME "问题" "默认"
  local var="$1" q="$2" def="$3" ans
  [ -n "${!var}" ] && return
  if [ -t 0 ]; then
    read -r -p "$q${def:+ [$def]}: " ans
    printf -v "$var" '%s' "${ans:-$def}"
  fi
}
ask URL   "Hub 地址 (WORKO_URL)"                    "http://localhost:8080"
ask ID    "你的身份/邮箱 (WORKO_ID)"                 ""
ask TOKEN "Workspace 口令 (WORKO_TOKEN)"             ""
ask AGENT "本机 agent (WORKO_AGENT: claude|codex)"   "claude"

# 校验必填
err=()
[ -n "$URL" ] || err+=("--url")
[ -n "$ID" ]  || err+=("--id")
if [ ${#err[@]} -gt 0 ]; then
  echo "[worko] 缺少必填: ${err[*]}" >&2
  echo "        非交互运行请传参，例如：" >&2
  echo "        init.sh --url http://hub:8080 --id you@corp.com --token <口令> --agent codex" >&2
  exit 1
fi

URL="${URL%/}"  # 去掉尾斜杠，否则拼出 $URL/agents 会变成 //agents

# 加入 workspace 时用 token 把 room id 取回来存进 config：
#  1) 之后发消息直接带正确 room，不再出现 "room not in workspace" 403；
#  2) 顺带体检 token/连接——取不到就当场报警，而不是等第一次 ask 才发现。
# 取不到（离线/token 错）就留空：发消息时服务器仍会按 token 兜底解析，不至于卡死。
if [ -z "$ROOM" ] && command -v python3 >/dev/null 2>&1; then
  auth=(); [ -n "$TOKEN" ] && auth=(-H "authorization: Bearer $TOKEN")
  # 只在 /rooms 恰好返回 1 个 room 时才采用：
  #  - authed 模式：token 把结果锁在你的 workspace，永远 1 个 → 取到的就是对的；
  #  - dev 模式(无 ADMIN_TOKEN)：/rooms 返回所有 workspace 的 room，>1 个根本分不清哪个是你的 → 放弃。
  ROOM=$(curl -fsS -m 5 "${auth[@]}" "$URL/rooms" 2>/dev/null | python3 -c '
import json,sys
try:
    r = json.load(sys.stdin).get("rooms") or []
    print(r[0]["id"] if len(r) == 1 else "")
except Exception: pass' 2>/dev/null) || ROOM=""
  [ -n "$ROOM" ] || echo "[worko] 提示：没唯一确定 room（连不上 / token 不对 / dev 模式有多个 workspace）。留空即可，发消息时服务器按 token 兜底解析。" >&2
fi

umask 077
mkdir -p "$(dirname "$CONFIG")"
# export：start.sh source 后 gateway 子进程才拿得到这些变量。
cat > "$CONFIG" <<EOF
export WORKO_URL=$URL
export WORKO_ID=$ID
export WORKO_TOKEN=$TOKEN
export WORKO_AGENT=$AGENT
export WORKO_AGENT_CWD=$WORKO_AGENT_CWD
${ROOM:+export WORKO_ROOM=$ROOM}
EOF
echo "[worko] 已写 $CONFIG"
echo "        id=$ID  url=$URL  agent=$AGENT  token=${TOKEN:+已设}  room=${ROOM:-未取到(运行时兜底)}  workdir=$WORKO_AGENT_CWD"
