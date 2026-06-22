#!/usr/bin/env bash
# worko update — update the installed worko skill to the latest version.
#   update.sh                              pull latest from the default GitHub repo, overwrite the skill in place
#   update.sh --from /path/to/open-worko   update from a local repo (useful during development / before pushing)
#   update.sh --repo owner/repo --ref dev  specify a different source repo / branch
#
# Note: all logic is wrapped in main() so bash reads the whole file before executing —
# overwriting this script mid-run won't corrupt execution.
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
      -h|--help) echo "Usage: update.sh [--from local-repo-path] [--repo owner/repo] [--ref branch]"; return 0;;
      *) echo "Unknown argument: $1" >&2; return 1;;
    esac
  done

  # Target = the skill directory containing this script (parent of scripts/)
  local HERE DEST
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DEST="$(cd "$HERE/.." && pwd)"
  [ -f "$DEST/SKILL.md" ] || { echo "[worko] This doesn't look like a worko skill directory: $DEST" >&2; return 1; }

  local TMP; TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' RETURN

  local SRC
  if [ -n "$FROM" ]; then
    SRC="$FROM/$PATH_IN_REPO"
    [ -d "$SRC" ] || { echo "[worko] Local source does not contain $SRC" >&2; return 1; }
    echo "[worko] Updating from local $SRC..."
  else
    echo "[worko] Pulling $PATH_IN_REPO from github.com/$REPO ($REF)..."
    git clone --depth 1 --branch "$REF" --filter=blob:none --sparse \
      "https://github.com/$REPO.git" "$TMP/repo" >/dev/null 2>&1 \
      || { echo "[worko] git clone failed (check repo/branch/network; private repos need GITHUB_TOKEN)" >&2; return 1; }
    ( cd "$TMP/repo" && git sparse-checkout set "$PATH_IN_REPO" >/dev/null 2>&1 )
    SRC="$TMP/repo/$PATH_IN_REPO"
    [ -d "$SRC" ] || { echo "[worko] $PATH_IN_REPO not found in repo" >&2; return 1; }
  fi

  # Only overwrite skill files; ~/.worko (your config / runtime state) is untouched.
  cp -R "$SRC/." "$DEST/"
  chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true
  echo "[worko] Updated $DEST"
  echo "        Codex requires a restart to pick up the new skill; script-only changes (ask/list/start) take effect immediately."
}

main "$@"
