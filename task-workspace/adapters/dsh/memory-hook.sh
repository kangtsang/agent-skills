#!/usr/bin/env bash
# memory-hook.sh - dsh (DeepSeek Harness) adapter.
#
# DSH loads the instruction-file chain ($DSH_HOME/AGENTS.md + per-directory
# AGENTS.md/CLAUDE.md) and skills; it has no per-directory external memory dir
# to link across worktrees. So this hook is intentionally a no-op.
#
# Usage:
#   memory-hook.sh link   <worktree-posix> <source-posix>
#   memory-hook.sh unlink <worktree-posix>
set -euo pipefail

case "$1" in
  link|unlink)
    echo "  memory already shared via $DSH_HOME/AGENTS.md + in-repo AGENTS.md (nothing to link)"
    ;;
  *)
    echo "usage: memory-hook.sh link <worktree-posix> <source-posix> | unlink <worktree-posix>" >&2
    exit 1 ;;
esac
