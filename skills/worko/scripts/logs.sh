#!/usr/bin/env bash
# worko logs — tail the gateway daemon log.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_config.sh"
ID="${WORKO_ID:-}"; [ -n "$ID" ] || { echo "WORKO_ID is required" >&2; exit 1; }
RUN="${WORKO_RUNDIR:-$HOME/.worko/run}"; LOG="$RUN/$ID.log"
[ -f "$LOG" ] || { echo "No log yet (run start.sh first)" >&2; exit 1; }
tail -f "$LOG"
