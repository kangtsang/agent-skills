#!/usr/bin/env bash
# memory-hook.sh - opencode adapter.
#
# opencode keeps instructions/rules in the repo (AGENTS.md / CLAUDE.md, with
# global and project scopes), which travel with the worktree. It has no
# per-directory external memory dir, so there is nothing to link across
# worktrees: this hook is intentionally a no-op.
#
# Usage:
#   memory-hook.sh link   <worktree-posix> <source-posix>
#   memory-hook.sh unlink <worktree-posix>
set -euo pipefail

case "$1" in
  link|unlink)
    echo "  memory already shared via in-repo AGENTS.md (nothing to link)"
    ;;
  *)
    echo "usage: memory-hook.sh link <worktree-posix> <source-posix> | unlink <worktree-posix>" >&2
    exit 1 ;;
esac
