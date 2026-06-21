#!/usr/bin/env bash
# worko init —— 写 ~/.worko/config。
# 两种用法：
#   人（终端里跑）：缺啥就交互问。      init.sh
#   agent（无 TTY）：把值当参数传。     init.sh --url U --id I --token T --agent codex
set -euo pipefail
CONFIG="${WORKO_CONFIG:-$HOME/.worko/config}"

URL="${WORKO_URL:-}"; ID="${WORKO_ID:-}"; TOKEN="${WORKO_TOKEN:-}"; AGENT="${WORKO_AGENT:-}"
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

umask 077
mkdir -p "$(dirname "$CONFIG")"
cat > "$CONFIG" <<EOF
WORKO_URL=$URL
WORKO_ID=$ID
WORKO_TOKEN=$TOKEN
WORKO_AGENT=$AGENT
EOF
echo "[worko] 已写 $CONFIG"
echo "        id=$ID  url=$URL  agent=$AGENT  token=${TOKEN:+已设}"
