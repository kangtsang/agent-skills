#!/usr/bin/env bash
# task-new.sh - create an isolated task workspace for one task/feature.
#
# Creates <tasks-root>/<project>/<task>/ holding a git worktree of every source
# repository under <source-root> (or only the repos named on the command line),
# each checked out on a new branch <prefix><task>. The project layer is the
# source root's own directory name, so two projects can hold tasks of the same
# name without colliding. The task directory is a plain folder, not a git repo
# itself: the agent session started there can edit and commit in each repository
# independently, without touching any other session's files or branches. If
# <source-root> is itself a single git repository, that repository is used
# directly.
#
# The task container lives OUTSIDE the source root by design - nested layouts
# are rejected so work and source stay isolated.
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
#   --prefix <p>        branch prefix (default: task/)
#   --base <ref>        start-point for the new branch in each repository
#                       (default: each repository's current HEAD)
#   --share-memory      link each worktree's auto-memory to the source root's
#                       via the agent's memory hook (see --agent); off by default
#   --agent <name>      agent whose memory hook to use for --share-memory
#                       (default: claude, or $TASK_WORKSPACE_AGENT)
#   --push              push the new branch to origin and set upstream tracking
#                       (only when the user explicitly asks; default is local).
#                       A rollback only removes the local branch - a branch
#                       already pushed stays on the remote.
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
  awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
}

# --- defaults -------------------------------------------------------------
SRC="${TASK_WORKSPACE_SRC:-$(pwd)}"
TASKS_ROOT="${TASK_WORKSPACE_ROOT:-}"
PREFIX="${TASK_BRANCH_PREFIX:-task/}"
BASE=""
TASK=""
REPOS=()
AGENT="${TASK_WORKSPACE_AGENT:-claude}"
SHARE_MEMORY=0
MEMORY_SHARED=0
PUSH=0
PUSH_OK=0
PUSH_FAILED=0

# What this run made, so a failure can take back exactly that and nothing else.
CREATED_REPOS=()
CREATED_WORKTREES=()
CREATED_BRANCHES=()
TASK_DIR_CREATED=0
PROJECT_DIR_CREATED=0

# --- parse arguments ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    --src)        SRC="$2";        shift 2 ;;
    --tasks-root) TASKS_ROOT="$2"; shift 2 ;;
    --prefix)     PREFIX="$2";     shift 2 ;;
    --base)       BASE="$2";       shift 2 ;;
    --share-memory) SHARE_MEMORY=1; shift ;;
    --agent)       AGENT="$2";      shift 2 ;;
    --push)        PUSH=1;         shift ;;
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
require_valid_task_name "$TASK"

# Normalize paths (E:\foo and E:/foo both work).
SRC="$(to_posix_path "$SRC")"
SRC="$(cd "$SRC" && pwd)"

if [ -z "$TASKS_ROOT" ]; then
  TASKS_ROOT="$(default_tasks_root "$SRC")"
  echo "tasks root (default): $TASKS_ROOT"
fi
TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"
TASKS_ROOT="${TASKS_ROOT%/}"

# Work and source must not nest inside each other, and the container must not be
# a repository or sit inside one.
require_isolated "$SRC" "$TASKS_ROOT" || exit 1
require_container_ok "$TASKS_ROOT" || exit 1

PROJECT="$(project_name_for "$SRC")"
if [ -z "$PROJECT" ] || [ "$PROJECT" = "/" ] || [ "$PROJECT" = "." ] || [ "$PROJECT" = ".." ]; then
  echo "task-new: the source root has no usable directory name: $SRC" >&2
  exit 1
fi

PROJECT_DIR="$TASKS_ROOT/$PROJECT"
TASK_DIR="$PROJECT_DIR/$TASK"
BRANCH="$PREFIX$TASK"

# --- discover source repositories ------------------------------------------
# A source repo is a top-level subdirectory of SRC whose .git is a real
# directory. Linked worktrees have .git as a file and are excluded, as are
# any *.worktrees directories.
discover_repos() {
  local d name
  # Single-repo source: the source root is itself a git repository.
  if [ -d "$SRC/.git" ]; then
    printf '%s\n' "$SRC"
    return
  fi
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

# --- rollback --------------------------------------------------------------
# Undo what this run made: the worktrees it created, the branches it created,
# and the directories it created. Nothing that existed before is touched - the
# validation above refused to start if the task directory or any branch was
# already there. A step that cannot be undone is named rather than hidden.
rollback() {
  local rc=$? i repo wt br
  trap - EXIT
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo "error: creating the task space failed; rolling back what this run made" >&2
  for (( i=${#CREATED_REPOS[@]}-1; i>=0; i-- )); do
    repo="${CREATED_REPOS[$i]}"
    wt="${CREATED_WORKTREES[$i]}"
    br="${CREATED_BRANCHES[$i]}"
    # Ask git first; it knows whether the worktree was ever registered. If the
    # removal fails, the directory is removed directly and the stale
    # registration pruned - otherwise the branch would still count as checked
    # out there and could not be deleted.
    if ! git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; then
      if [ -d "$wt" ]; then
        if require_direct_child "$TASK_DIR" "$wt" && require_real_dir "$wt"; then
          rm -rf -- "$wt" || echo "  left behind: $wt (remove it by hand)" >&2
        else
          echo "  left behind: $wt (remove it by hand)" >&2
        fi
      fi
      git -C "$repo" worktree prune >/dev/null 2>&1 || true
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$br"; then
      if ! git -C "$repo" branch -D -- "$br" >/dev/null 2>&1; then
        echo "  left behind: branch $br in $repo (delete it by hand)" >&2
      fi
    fi
  done
  if [ "$TASK_DIR_CREATED" -eq 1 ]; then
    rmdir -- "$TASK_DIR" 2>/dev/null || true
  fi
  if [ "$PROJECT_DIR_CREATED" -eq 1 ]; then
    rmdir -- "$PROJECT_DIR" 2>/dev/null || true
  fi
  exit "$rc"
}

# --- create ----------------------------------------------------------------
mkdir -p -- "$TASKS_ROOT"
ensure_container_readme "$TASKS_ROOT"
if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p -- "$PROJECT_DIR"
  PROJECT_DIR_CREATED=1
fi
trap rollback EXIT
mkdir -- "$TASK_DIR" || exit 1
TASK_DIR_CREATED=1

for repo in "${REPOS[@]}"; do
  name="$(basename "$repo")"
  worktree="$TASK_DIR/$name"
  echo "worktree: $name -> $worktree [$BRANCH from ${BASE:-HEAD}]"
  CREATED_REPOS+=("$repo")
  CREATED_WORKTREES+=("$worktree")
  CREATED_BRANCHES+=("$BRANCH")
  if [ -n "$BASE" ]; then
    git -C "$repo" worktree add "$worktree" -b "$BRANCH" "$BASE" >/dev/null || exit 1
  else
    git -C "$repo" worktree add "$worktree" -b "$BRANCH" >/dev/null || exit 1
  fi
  if [ "$PUSH" -eq 1 ]; then
    if git -C "$repo" push -u origin "$BRANCH"; then
      PUSH_OK=1
    else
      PUSH_FAILED=1
      echo "  WARN: push to origin failed for '$name' (branch kept locally)" >&2
    fi
  fi
done

# --- optionally share auto-memory with the source session ------------------
if [ "$SHARE_MEMORY" -eq 1 ]; then
  hook="$(memory_hook_for "$AGENT")"
  if [ ! -f "$hook" ]; then
    echo "task-new: no memory hook for agent '$AGENT' ($hook); --share-memory skipped" >&2
  else
    for repo in "${REPOS[@]}"; do
      if bash "$hook" link "$TASK_DIR/$(basename "$repo")" "$SRC"; then
        MEMORY_SHARED=1
      fi
    done
  fi
fi

# --- leave a breadcrumb for the agent session ------------------------------
{
  echo "# Task: $TASK"
  echo
  echo "- Project: \`$PROJECT\`"
  echo "- Branch: \`$BRANCH\` (one branch per repository below)"
  if [ -n "$BASE" ]; then
    echo "- Base: \`$BASE\`"
  else
    echo "- Base: each repository's current HEAD"
  fi
  echo "- Created: $(date '+%Y-%m-%d %H:%M')"
  echo "- Source root: \`$SRC\`"
  echo "- Layout: \`$TASK_DIR\`"
  echo "- Agent: \`$AGENT\`"
  if [ "$MEMORY_SHARED" -eq 1 ]; then
    echo "- Share memory: yes"
  fi
  if [ "$PUSH_OK" -eq 1 ]; then
    echo "- Remote: pushed to \`origin/$BRANCH\`"
  fi
  echo "- This folder is the agent session working directory."
  echo
  echo "## Repositories"
  for repo in "${REPOS[@]}"; do echo "- \`$(basename "$repo")\`"; done
  echo
  echo "## Conventions"
  echo "- Commit in each repository separately (same branch name everywhere)."
  echo "- Source repositories are read-only: never edit or commit there."
  echo "- Finish with \`task-done.sh $PROJECT/$TASK --tasks-root $(printf '%q' "$TASKS_ROOT")\`;"
  echo "  by default it removes the worktrees and keeps the branch and stray files."
} > "$TASK_DIR/README.md"

trap - EXIT

echo "workspace is ready: $TASK_DIR"
echo "Start a session there with cd $TASK_DIR && $AGENT."
if is_windows; then
  echo "  Windows native: cd $(cygpath -w "$TASK_DIR") && $AGENT."
fi
if [ "$PUSH_FAILED" -eq 1 ]; then
  echo "warning: one or more branches failed to push (kept local)" >&2
fi