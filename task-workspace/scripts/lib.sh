#!/usr/bin/env bash
# Shared helpers for the task-workspace scripts.

# Normalize a Windows (E:\x, E:/x) or POSIX path to a POSIX path.
to_posix_path() {
  local p="$1"
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):(.*)$ ]]; then
    printf '/%s%s\n' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[2]}"
  else
    printf '%s\n' "$p"
  fi
}

# Default location for the task workspace container, given the source root.
# Prefers a folder directly under the source root's drive:
#   <drive>:\workspace        when free
#   <drive>:\worktree-space   otherwise (created, or reused if it exists)
# Falls back to a sibling of the source root when no drive letter can be
# determined (UNC paths, non-Windows environments).
default_tasks_root() {
  local src="$1" winpath drive
  winpath="$(cygpath -m "$src" 2>/dev/null || true)"
  if [[ "$winpath" =~ ^([A-Za-z]): ]]; then
    drive="${winpath:0:1}"
    drive="${drive,,}"
    if [ ! -e "/$drive/workspace" ]; then
      printf '/%s/workspace\n' "$drive"
    else
      printf '/%s/worktree-space\n' "$drive"
    fi
  else
    printf '%s/worktree-space\n' "$(dirname "$src")"
  fi
}

# Fail when the task container and the source root nest inside each other
# (or are the same directory): work and source must stay isolated.
require_isolated() {
  local src="$1" tasks_root="$2"
  if [ "$src" = "$tasks_root" ]; then
    echo "error: tasks root must not be the source root itself: $src" >&2
    return 1
  fi
  case "$tasks_root/" in
    "$src"/*)
      echo "error: tasks root is inside the source root: $tasks_root" >&2
      echo "  work and source must be isolated; pick a location outside the source tree" >&2
      return 1 ;;
  esac
  case "$src/" in
    "$tasks_root"/*)
      echo "error: source root is inside the tasks root: $tasks_root" >&2
      echo "  work and source must be isolated; pick a location outside the source tree" >&2
      return 1 ;;
  esac
  return 0
}
