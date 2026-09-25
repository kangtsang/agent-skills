#!/usr/bin/env bash
# memory-hook.sh - codex (OpenAI Codex CLI) adapter.
#
# Codex keeps instructions in AGENTS.md (global ~/.codex/AGENTS.md + per-repo
# AGENTS.md) and memories in the global ~/.codex/memories/ directory. Neither
# is keyed by working directory, so there is nothing to link across worktrees:
# this hook is intentionally a no-op.
#
# Usage:
#   memory-hook.sh link   <worktree-posix> <source-posix>
#   memory-hook.sh unlink <worktree-posix>
set -euo pipefail

case "$1" in
  link|unlink)
    echo "  memory already shared via ~/.codex/ (global) + in-repo AGENTS.md (nothing to link)"
    ;;
  *)
    echo "usage: memory-hook.sh link <worktree-posix> <source-posix> | unlink <worktree-posix>" >&2
    exit 1 ;;
esac
