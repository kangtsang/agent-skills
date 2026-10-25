#!/usr/bin/env bash
# task-list.sh - list task workspaces and the state of their worktrees.
#
# Reads both layouts: <container>/<project>/<task> (current) and
# <container>/<task> (before the project layer). A task directory is one that
# holds at least one linked worktree.
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
    -h|--help)    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --tasks-root) TASKS_ROOT="$2"; shift 2 ;;
    *)            echo "task-list: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TASKS_ROOT" ]; then
  TASKS_ROOT="$(default_tasks_root "$(pwd)")"
fi
TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"
TASKS_ROOT="${TASKS_ROOT%/}"

if [ ! -d "$TASKS_ROOT" ]; then
  echo "no task container found: $TASKS_ROOT"
  exit 0
fi

print_task() {
  local project="$1" dir="$2" label child branch dirty found
  label="$(basename "$dir")"
  [ -n "$project" ] && label="$project/$label"
  echo "$label"
  found=0
  for child in "$dir"/*/; do
    [ -d "$child" ] || continue
    is_linked_worktree "${child%/}" || continue
    found=1
    branch="$(git -C "${child%/}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    [ "$branch" = "HEAD" ] && branch="detached"
    dirty="$(git -C "${child%/}" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
    echo "  $(basename "${child%/}")   $branch   (dirty files: $dirty)"
  done
  [ "$found" -eq 1 ] || echo "  (no git worktrees)"
}

for entry in "$TASKS_ROOT"/*/; do
  [ -d "$entry" ] || continue
  entry="${entry%/}"
  if is_task_dir "$entry"; then
    print_task "" "$entry"
    continue
  fi
  project="$(basename "$entry")"
  for sub in "$entry"/*/; do
    [ -d "$sub" ] || continue
    if is_task_dir "${sub%/}"; then
      print_task "$project" "${sub%/}"
    fi
  done
done