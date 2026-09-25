#!/usr/bin/env bash
# task-new.sh - create an isolated task workspace for one task/feature.
#
# Creates <tasks-root>/<task>/ containing a git worktree of every source
# repository under <source-root> (or only the repos named on the command
# line), each checked out on a new branch <prefix><task>. The task
# directory is a plain folder, not a git repo itself: the agent session
# started there can edit and commit in each repository independently,
# without touching any other session's files or branches.
#
# The task container lives OUTSIDE the source root by design - nested
# layouts are rejected so work and source stay isolated.
#
# Usage:
#   task-new.sh <task-name> [repo ...] [options]
#
#   <task-name>  task identifier, also used for the branch name
#   [repo ...]   repository names under <source-root>; omit to use all
#                discovered repositories
#
# Options:
#   --src <path>        source root containing the repositories
#                       (default: current directory, or $TASK_WORKSPACE_SRC)
#   --tasks-root <path> task container root (default: $TASK_WORKSPACE_ROOT,
#                       else the drive-root recommendation, see
#                       suggest-tasks-root.sh / default_tasks_root)
#   --prefix <p>        branch prefix (default: feat/)
#   --base <ref>        start-point for the new branch in each repository
#                       (default: each repository's current HEAD)
#   -h, --help          show this help
#
# Environment:
#   TASK_WORKSPACE_SRC     source root
#   TASK_WORKSPACE_ROOT    task container root
#   TASK_BRANCH_PREFIX     branch prefix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

# --- defaults -------------------------------------------------------------
SRC="${TASK_WORKSPACE_SRC:-$(pwd)}"
TASKS_ROOT="${TASK_WORKSPACE_ROOT:-}"
PREFIX="${TASK_BRANCH_PREFIX:-feat/}"
BASE=""
TASK=""
REPOS=()

# --- parse arguments ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    --src)        SRC="$2";        shift 2 ;;
    --tasks-root) TASKS_ROOT="$2"; shift 2 ;;
    --prefix)     PREFIX="$2";     shift 2 ;;
    --base)       BASE="$2";       shift 2 ;;
    --)           shift; break ;;
    -*)           echo "task-new: unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)            if [ -z "$TASK" ]; then TASK="$1"; else REPOS+=("$1"); fi; shift ;;
  esac
done

if [ -z "$TASK" ]; then
  echo "task-new: missing <task-name>" >&2
  usage >&2
  exit 1
fi
case "$TASK" in
  */*|*\\*|*[[:space:]]*)
    echo "task-new: task name must not contain /, \\ or whitespace: $TASK" >&2
    exit 1 ;;
esac

# Normalize paths (E:\foo and E:/foo both work).
SRC="$(to_posix_path "$SRC")"
SRC="$(cd "$SRC" && pwd)"

if [ -z "$TASKS_ROOT" ]; then
  TASKS_ROOT="$(default_tasks_root "$SRC")"
  echo "tasks root (default): $TASKS_ROOT"
fi
TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"

# Work and source must not nest inside each other.
require_isolated "$SRC" "$TASKS_ROOT" || exit 1

TASK_DIR="$TASKS_ROOT/$TASK"
BRANCH="$PREFIX$TASK"

# --- discover source repositories ------------------------------------------
# A source repo is a top-level subdirectory of SRC whose .git is a real
# directory. Linked worktrees have .git as a file and are excluded, as are
# any *.worktrees directories.
discover_repos() {
  local d name
  for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case "$name" in
      *.worktrees|.*) continue ;;
    esac
    [ -d "$d/.git" ] && printf '%s\n' "${d%/}"
  done
}

if [ ${#REPOS[@]} -eq 0 ]; then
  while IFS= read -r p; do REPOS+=("$p"); done < <(discover_repos)
  if [ ${#REPOS[@]} -eq 0 ]; then
    echo "task-new: no source repositories found under $SRC" >&2
    echo "  (expected .git directories in its top-level subdirectories;" >&2
    echo "   a git worktree checkout is not a source root)" >&2
    exit 1
  fi
else
  for i in "${!REPOS[@]}"; do
    [ -d "$SRC/${REPOS[$i]}/.git" ] || {
      echo "task-new: not a source repository: ${REPOS[$i]}" >&2
      exit 1
    }
    REPOS[$i]="$SRC/${REPOS[$i]}"
  done
fi

# --- validate --------------------------------------------------------------
if [ -e "$TASK_DIR" ]; then
  echo "task-new: task workspace already exists: $TASK_DIR" >&2
  exit 1
fi
for repo in "${REPOS[@]}"; do
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "task-new: branch '$BRANCH' already exists in '$(basename "$repo")'; pick another task name" >&2
    exit 1
  fi
done

if [ -n "$BASE" ]; then
  for repo in "${REPOS[@]}"; do
    if ! git -C "$repo" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
      echo "task-new: base '$BASE' not found in '$(basename "$repo")'" >&2
      exit 1
    fi
  done
fi

# --- create worktrees ------------------------------------------------------
mkdir -p "$TASKS_ROOT"
mkdir "$TASK_DIR"
for repo in "${REPOS[@]}"; do
  echo "worktree: $(basename "$repo") -> $TASK_DIR/$(basename "$repo") [$BRANCH from ${BASE:-HEAD}]"
  if [ -n "$BASE" ]; then
    git -C "$repo" worktree add "$TASK_DIR/$(basename "$repo")" -b "$BRANCH" "$BASE" >/dev/null
  else
    git -C "$repo" worktree add "$TASK_DIR/$(basename "$repo")" -b "$BRANCH" >/dev/null
  fi
done

# --- leave a breadcrumb for the agent session ------------------------------
{
  echo "# Task: $TASK"
  echo
  echo "- Branch: \`$BRANCH\` (one branch per repository below)"
  if [ -n "$BASE" ]; then
    echo "- Base: \`$BASE\`"
  else
    echo "- Base: each repository's current HEAD"
  fi
  echo "- Created: $(date '+%Y-%m-%d %H:%M')"
  echo "- Source root: \`$SRC\`"
  echo "- This folder is the agent session working directory."
  echo
  echo "## Repositories"
  for repo in "${REPOS[@]}"; do echo "- \`$(basename "$repo")\`"; done
  echo
  echo "## Conventions"
  echo "- Commit in each repository separately (same branch name everywhere)."
  echo "- Source repositories are read-only: never edit or commit there."
  echo "- Merging back to the main branch is done by the user, not the agent,"
  echo "  via \`task-done.sh $TASK\`."
} > "$TASK_DIR/README.md"

echo
echo "Task workspace ready: $TASK_DIR"
echo "Start the agent session there:"
echo "  cd $TASK_DIR && claude"
