# Locate the worko config file (sourced by each .sh script). Sets $CONFIG and sources it if found.
# Priority:
#   1) WORKO_CONFIG — explicit path, highest priority
#   2) Walk up from current directory to find the nearest .worko/config — project-level
#   3) ~/.worko/config — machine-level fallback
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
