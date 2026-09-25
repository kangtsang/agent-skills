#!/usr/bin/env bash
# task-done.sh - merge a finished task workspace back and remove it.
#
# For every git worktree inside the task directory: (optionally) merge its
# branch into a target branch, remove the worktree, and (optionally) delete
# the branch. By default it only removes the worktrees and keeps the
# branches; merging and branch deletion must be requested explicitly.
#
# Usage:
#   task-done.sh <task-name-or-path> [options]
#
#   <task>  name under <tasks-root>, or a directory path (also "."
#           when run from inside the task directory)
#
# Options:
#   --merge         merge the branch into the target branch before removing
#                   the worktree (default: NO merge)
#   --delete-branch delete the branch after a successful merge (requires
#                   --merge; default: keep the branch)
#   --no-merge      explicit alias for the default (no merge)
#   --target <b>    merge target branch (default: auto-detect from
#                   origin/HEAD, then main, then master)
#   --force         force-remove dirty worktrees and force-delete branches
#   --tasks-root <path>  task container root (default: $TASK_WORKSPACE_ROOT,
#                   else the drive-root recommendation)
#   -h, --help      show this help
#
# Environment:
#   TASK_WORKSPACE_ROOT    task container root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

# --- defaults -------------------------------------------------------------
TASKS_ROOT="${TASK_WORKSPACE_ROOT:-}"
TASK=""
MERGE=0
DELETE_BRANCH=0
FORCE=0
TARGET=""

# --- parse arguments ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)       usage; exit 0 ;;
    --merge)         MERGE=1;        shift ;;
    --no-merge)      MERGE=0;        shift ;;
    --delete-branch) DELETE_BRANCH=1; shift ;;
    --force)         FORCE=1;        shift ;;
    --target)        TARGET="$2";    shift 2 ;;
    --tasks-root)    TASKS_ROOT="$2"; shift 2 ;;
    --)              shift; break ;;
    -*)              echo "task-done: unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)               TASK="$1"; shift ;;
  esac
done

if [ "$DELETE_BRANCH" -eq 1 ] && [ "$MERGE" -ne 1 ]; then
  echo "task-done: --delete-branch requires --merge (a branch is only deleted after it is merged)" >&2
  exit 1
fi

if [ -z "$TASK" ]; then
  echo "task-done: missing <task-name-or-path>" >&2
  usage >&2
  exit 1
fi

# Resolve the task directory: an existing path wins, otherwise look under
# <tasks-root>/.
if [ -d "$TASK" ]; then
  TASK_DIR="$(to_posix_path "$TASK")"
  TASK_DIR="$(cd "$TASK_DIR" && pwd)"
else
  if [ -z "$TASKS_ROOT" ]; then
    TASKS_ROOT="$(default_tasks_root "$(pwd)")"
  fi
  TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"
  TASK_DIR="$TASKS_ROOT/$TASK"
  [ -d "$TASK_DIR" ] || {
    echo "task-done: no such task workspace: $TASK_DIR" >&2
    echo "  (pass --tasks-root if the container is not in the default location)" >&2
    exit 1
  }
fi

# Collect the worktrees inside the task directory.
#
# Guard against the source root being mistaken for a task: a linked
# worktree's `.git` is a FILE (a gitdir pointer), whereas a source
# repository / main working tree has `.git` as a DIRECTORY. Requiring a
# file excludes source repos; the main-tree check below is a second line
# of defence.
WORKTREES=()
for w in "$TASK_DIR"/*/; do
  [ -d "$w" ] || continue
  [ -f "$w/.git" ] || continue
  w="${w%/}"
  main_tree="$(git -C "$w" worktree list --porcelain | sed -n '1s/^worktree //p')"
  [ "$main_tree" != "$w" ] || continue
  WORKTREES+=("$w")
done
if [ ${#WORKTREES[@]} -eq 0 ]; then
  echo "task-done: no git worktrees found in $TASK_DIR" >&2
  exit 1
fi

# --- process each worktree -------------------------------------------------
FAILED=0
for w in "${WORKTREES[@]}"; do
  name="$(basename "$w")"
  branch="$(git -C "$w" rev-parse --abbrev-ref HEAD)"
  # Locate the source (main) repository. `rev-parse --git-common-dir` can
  # return mangled mixed-format paths on Windows/MSYS, but `worktree list`
  # always prints the main worktree first.
  main_repo="$(git -C "$w" worktree list --porcelain | sed -n '1s/^worktree //p')"
  if [ -z "$main_repo" ]; then
    echo "  ERROR: cannot locate the source repository for $name" >&2
    FAILED=1
    continue
  fi

  echo "== $name (branch: $branch)"

  if [ "$MERGE" -eq 1 ]; then
    # Pick the merge target: explicit --target, else origin/HEAD, else the
    # first of main/master that exists.
    target="$TARGET"
    if [ -z "$target" ]; then
      target="$(git -C "$main_repo" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's#^refs/remotes/[^/]*/##' || true)"
    fi
    if [ -z "$target" ] || ! git -C "$main_repo" show-ref --verify --quiet "refs/heads/$target"; then
      target=""
      for t in main master; do
        if git -C "$main_repo" show-ref --verify --quiet "refs/heads/$t"; then target="$t"; break; fi
      done
    fi
    if [ -z "$target" ]; then
      echo "  ERROR: cannot determine merge target (tried origin/HEAD, main, master); use --target" >&2
      FAILED=1
      continue
    fi

    if ! git -C "$main_repo" merge --no-ff --no-edit "$branch"; then
      git -C "$main_repo" merge --abort 2>/dev/null || true
      echo "  ERROR: merge of '$branch' into '$target' failed (conflict or dirty worktree?); worktree and branch kept" >&2
      FAILED=1
      continue
    fi
    echo "  merged '$branch' -> '$target' (--no-ff)"
  fi

  wt_flags=()
  [ "$FORCE" -eq 1 ] && wt_flags+=(--force)
  if ! git -C "$main_repo" worktree remove "${wt_flags[@]}" "$w"; then
    echo "  ERROR: failed to remove worktree (uncommitted changes? use --force)" >&2
    FAILED=1
    continue
  fi
  echo "  worktree removed"

  if [ "$DELETE_BRANCH" -eq 1 ]; then
    if [ "$FORCE" -eq 1 ]; then
      git -C "$main_repo" branch -D "$branch"
    else
      if ! git -C "$main_repo" branch -d "$branch"; then
        echo "  WARN: branch '$branch' not deleted" >&2
      fi
    fi
    echo "  branch '$branch' deleted"
  else
    echo "  branch '$branch' kept"
  fi
done

# --- clean up the task directory -------------------------------------------
# Empty the task directory of stray files (IDE caches, the README breadcrumb,
# etc.). A worktree kept by a failed removal above still holds its `.git`
# pointer and is left untouched.
find "$TASK_DIR" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | \
  while IFS= read -r -d '' leftover; do
    [ -e "$leftover/.git" ] && continue
    rm -rf -- "$leftover" || true
  done
if rmdir "$TASK_DIR" 2>/dev/null; then
  echo "task directory removed: $TASK_DIR"
else
  echo "note: task directory kept (worktrees still present): $TASK_DIR"
fi

if [ "$FAILED" -eq 1 ]; then
  echo "task-done: finished with errors (see above)" >&2
  exit 1
fi
echo "task-done: complete"
