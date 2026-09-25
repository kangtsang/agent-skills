#!/usr/bin/env bash
# suggest-tasks-root.sh - print the recommended task container location for
# a source root. The agent asks the user before creating anything; this
# script computes the default option to offer.
#
# Usage:
#   suggest-tasks-root.sh [<source-root>]   (default: current directory)
#
# Prints one POSIX path on stdout; whether it already exists is noted on
# stderr (an existing container is reused, not replaced).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

SRC="${1:-$(pwd)}"
SRC="$(to_posix_path "$SRC")"
SRC="$(cd "$SRC" && pwd)"

root="$(default_tasks_root "$SRC")"
printf '%s\n' "$root"
if [ -e "$root" ]; then
  echo "note: $root already exists and will be reused" >&2
fi
