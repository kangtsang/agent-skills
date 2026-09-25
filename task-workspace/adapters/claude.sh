#!/usr/bin/env bash
# claude.sh - Claude Code memory hook: share auto-memory across worktrees.
#
# Claude Code keys auto-memory by working directory:
#   ~/.claude/projects/<encoded-cwd>/memory
# where <encoded-cwd> is the absolute working-directory path with every
# ':', '\', '/' replaced by '-'. This layout is undocumented, so this hook is
# experimental and can silently break if the encoding or location changes.
#
# Only Claude Code isolates memory per directory; opencode/dsh/codex share the
# noop.sh hook because their memory is in-repo or global.
#
# Usage:
#   claude.sh link   <worktree-posix> <source-posix>
#   claude.sh unlink <worktree-posix>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib.sh"

projects_dir() {
  printf '%s/.claude/projects' "$HOME"
}

encode_project_dir() {
  printf '%s' "$1" | sed 's#[\\/:]#-#g'
}

# POSIX path of the auto-memory directory for a repo (absolute POSIX path).
memory_dir_for() {
  printf '%s/%s/memory' "$(projects_dir)" "$(encode_project_dir "$(cygpath -w "$1")")"
}

case "$1" in
  link)
    worktree="$2"; src="$3"
    if ! is_windows; then
      echo "claude hook: junction sharing requires Windows" >&2
      exit 1
    fi
    link="$(memory_dir_for "$worktree")"
    target="$(memory_dir_for "$src")"
    case "$link$target" in
      *\'*) echo "claude hook: paths containing ' are not supported" >&2; exit 1 ;;
    esac
    mkdir -p "$(dirname "$link")" "$target"
    powershell.exe -NoProfile -Command \
      "New-Item -ItemType Junction -Path '$(cygpath -w "$link")' -Target '$(cygpath -w "$target")' -ErrorAction Stop" >/dev/null 2>&1
    [ -d "$link" ] || { echo "claude hook: failed to create junction for '$(basename "$worktree")'" >&2; exit 1; }
    echo "  shared memory (junction): $(basename "$worktree")"
    ;;
  unlink)
    worktree="$2"
    link="$(memory_dir_for "$worktree")"
    cmd //c rmdir "$(cygpath -w "$link")" >/dev/null 2>&1 || true
    rmdir "$(dirname "$link")" 2>/dev/null || true
    ;;
  *)
    echo "usage: claude.sh link <worktree-posix> <source-posix> | unlink <worktree-posix>" >&2
    exit 1 ;;
esac
