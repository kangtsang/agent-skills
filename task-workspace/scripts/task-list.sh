#!/usr/bin/env bash
# task-list.sh - list task workspaces and the state of their worktrees.
#
# Usage:
#   task-list.sh [--tasks-root <path>]
#
# Environment:
#   TASK_WORKSPACE_ROOT    task container root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

TASKS_ROOT="${TASK_WORKSPACE_ROOT:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --tasks-root) TASKS_ROOT="$2"; shift 2 ;;
    *)            echo "task-list: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TASKS_ROOT" ]; then
  TASKS_ROOT="$(default_tasks_root "$(pwd)")"
fi
TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"

if [ ! -d "$TASKS_ROOT" ]; then
  echo "no task container found: $TASKS_ROOT"
  exit 0
fi

for taskdir in "$TASKS_ROOT"/*/; do
  [ -d "$taskdir" ] || continue
  echo "$(basename "$taskdir")"
  found=0
  for w in "$taskdir"*/; do
    [ -e "$w/.git" ] || continue
    found=1
    branch="$(git -C "$w" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    dirty="$(git -C "$w" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    echo "  $(basename "$w")   $branch   (dirty files: $dirty)"
  done
  [ "$found" -eq 1 ] || echo "  (no git worktrees)"
done
