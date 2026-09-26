#!/usr/bin/env bash
# noop.sh - shared no-op memory hook for agents whose memory is not keyed by
# working directory (opencode/dsh/codex keep instructions in in-repo AGENTS.md
# and/or global dirs, which already travel with or are shared by every
# worktree). Nothing to link, so this hook intentionally does nothing.
#
# Usage:
#   noop.sh link   <worktree-posix> <source-posix>
#   noop.sh unlink <worktree-posix>
set -euo pipefail

case "$1" in
  link|unlink)
    echo "  memory already shared (no per-directory memory to link)"
    ;;
  *)
    echo "usage: noop.sh link <worktree-posix> <source-posix> | unlink <worktree-posix>" >&2
    exit 1 ;;
esac
