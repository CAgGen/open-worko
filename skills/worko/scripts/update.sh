#!/usr/bin/env bash
# worko update —— 把已安装的 worko skill 更新到最新。
#   update.sh                              从默认 GitHub repo 拉最新，覆盖自己所在的 skill
#   update.sh --from /path/to/open-worko   从本地仓库更新（开发/没 push 时用）
#   update.sh --repo owner/repo --ref dev  指定来源/分支
#
# 注：整段逻辑包在 main() 里，bash 会先读完再执行——这样覆盖自身脚本也不会跑坏。
set -euo pipefail

main() {
  local REPO="${WORKO_SKILL_REPO:-CAgGen/open-worko}"
  local PATH_IN_REPO="${WORKO_SKILL_PATH:-skills/worko}"
  local REF="${WORKO_SKILL_REF:-main}"
  local FROM=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --from) FROM="$2"; shift 2;;
      --repo) REPO="$2"; shift 2;;
      --ref)  REF="$2";  shift 2;;
      -h|--help) echo "用法: update.sh [--from 本地仓库路径] [--repo owner/repo] [--ref 分支]"; return 0;;
      *) echo "未知参数: $1" >&2; return 1;;
    esac
  done

  # 目标 = 本脚本所在 skill 目录（scripts/ 的上一级）
  local HERE DEST
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DEST="$(cd "$HERE/.." && pwd)"
  [ -f "$DEST/SKILL.md" ] || { echo "[worko] 这看着不像 worko skill 目录: $DEST" >&2; return 1; }

  local TMP; TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' RETURN

  local SRC
  if [ -n "$FROM" ]; then
    SRC="$FROM/$PATH_IN_REPO"
    [ -d "$SRC" ] || { echo "[worko] 本地源没有 $SRC" >&2; return 1; }
    echo "[worko] 从本地 $SRC 更新…"
  else
    echo "[worko] 从 github.com/$REPO ($REF) 拉 $PATH_IN_REPO …"
    git clone --depth 1 --branch "$REF" --filter=blob:none --sparse \
      "https://github.com/$REPO.git" "$TMP/repo" >/dev/null 2>&1 \
      || { echo "[worko] git clone 失败（检查 repo/分支/网络；私有仓需 GITHUB_TOKEN）" >&2; return 1; }
    ( cd "$TMP/repo" && git sparse-checkout set "$PATH_IN_REPO" >/dev/null 2>&1 )
    SRC="$TMP/repo/$PATH_IN_REPO"
    [ -d "$SRC" ] || { echo "[worko] repo 里没有 $PATH_IN_REPO" >&2; return 1; }
  fi

  # 只覆盖 skill 文件，不碰 ~/.worko（你的 config / 运行产物都在那）
  cp -R "$SRC/." "$DEST/"
  chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true
  echo "[worko] 已更新 $DEST"
  echo "        Codex 需重启才认新 skill；纯脚本改动(ask/list/start)立即生效。"
}

main "$@"
