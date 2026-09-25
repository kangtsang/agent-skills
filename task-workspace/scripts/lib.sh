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

# --- Claude Code auto-memory sharing (experimental) ------------------------
# Claude Code keys per-project state (including auto-memory) under
#   ~/.claude/projects/<encoded-cwd>/memory
# where <encoded-cwd> is the absolute working-directory path with every
# ':', '\', '/' replaced by '-'. This layout is undocumented, so --share-memory
# relies on it and can silently break if the encoding or location changes.

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

claude_projects_dir() {
  printf '%s/.claude/projects' "$HOME"
}

# Encoded per-project directory name for an absolute Windows path.
encode_project_dir() {
  printf '%s' "$1" | sed 's#[\\/:]#-#g'
}

# POSIX path of the auto-memory directory for a project (absolute Windows path).
memory_dir_for() {
  printf '%s/%s/memory' "$(claude_projects_dir)" "$(encode_project_dir "$1")"
}

# Link a worktree's memory dir to the source's with a directory junction
# (works without admin). $1 and $2 are POSIX paths; returns non-zero on failure.
share_memory() {
  local link target
  case "$1$2" in
    *\'*) echo "task-workspace: share-memory does not support paths containing '" >&2; return 1 ;;
  esac
  link="$(cygpath -w "$1")"
  target="$(cygpath -w "$2")"
  mkdir -p "$(dirname "$1")" "$2"
  powershell.exe -NoProfile -Command \
    "New-Item -ItemType Junction -Path '$link' -Target '$target' -ErrorAction Stop" >/dev/null 2>&1
  [ -d "$1" ]
}

# Remove the junction only (never the target's contents); idempotent.
unshare_memory() {
  cmd //c rmdir "$(cygpath -w "$1")" >/dev/null 2>&1 || true
}
