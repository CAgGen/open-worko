# worko config 定位（被各 .sh 脚本 source）。设置 $CONFIG，存在就 source 进来。
# 优先级：
#   1) WORKO_CONFIG —— 显式指定，最高
#   2) 从当前目录向上找最近的 .worko/config —— 项目级（每个项目一个 config）
#   3) ~/.worko/config —— 机器级兜底
if [ -z "${WORKO_CONFIG:-}" ]; then
  _d="$PWD"
  while :; do
    if [ -f "$_d/.worko/config" ]; then WORKO_CONFIG="$_d/.worko/config"; break; fi
    [ "$_d" = "/" ] && break
    _d="$(dirname "$_d")"
  done
  unset _d
fi
CONFIG="${WORKO_CONFIG:-$HOME/.worko/config}"
[ -f "$CONFIG" ] && . "$CONFIG"
