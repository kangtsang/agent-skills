#!/usr/bin/env bash
# task-done.sh - merge a finished task workspace back and remove it.
#
# For every git worktree inside the task directory: (optionally) merge its
# branch into the branch the source repository has checked out, remove the
# worktree, and (optionally) delete the branch. By default it only removes the
# worktrees and keeps the branches and stray files; merging and branch deletion
# must be requested explicitly.
#
# Every readiness check runs before anything is changed: a worktree with
# uncommitted work, a worktree on a detached HEAD, or a source repository that
# is not on the requested target stops the whole finish with nothing merged and
# nothing removed. Use --force to discard uncommitted work (and to force-delete
# an unmerged branch).
#
# Usage:
#   task-done.sh <task-name-or-path> [options]
#
#   <task>  <task>, <project>/<task>, or a directory path (also "."
#           when run from inside the task directory)
#
# Options:
#   --merge         merge the branch into the target branch before removing
#                   the worktree (default: NO merge)
#   --delete-branch delete the branch after a successful merge (requires
#                   --merge; default: keep the branch)
#   --no-merge      explicit alias for the default (no merge)
#   --target <b>    merge target branch; must be the branch the source
#                   repository has checked out (default: that branch)
#   --force         discard uncommitted work in the worktrees and force-delete
#                   branches; destructive, only use it deliberately
#   --clean-stray   delete stray entries (non-git files) left in the task
#                   directory (default: keep them and list them)
#   --archive-docs  archive the user's own documents (anything that is not
#                   build output or editor state) into archived-docs/ under the
#                   container root, instead of deleting them
#   --docs-dir <dir>  archive destination (default:
#                     <tasks-root>/archived-docs/<project>/<task>-<timestamp>);
#                     implies --archive-docs
#   --keep <name>   keep this top-level stray entry (repeatable)
#   --project <p>   project layer, when a bare task name exists under more than
#                   one project
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
  awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
}

# Classify a stray entry: build output and editor state are disposable; the
# rest is the user's own content (plans, notes, anything not git-managed) and
# is worth archiving. Mirrors dsh-worktree-space's stray classification.
stray_is_content() {
  local name="$1" is_dir="$2"
  if [ "$is_dir" = 1 ]; then
    case "$name" in
      node_modules|dist|build|out|output|target|bin|obj|coverage|.cache|.next|.nuxt|.turbo|.parcel-cache|__pycache__|.pytest_cache|.gradle|.m2|.venv|venv|vendor|.idea|.vscode|.vs)
        return 1 ;;
    esac
    return 0
  fi
  case "$name" in
    .DS_Store|Thumbs.db|desktop.ini|*.o|*.obj|*.pyc|*.pyo|*.class|*.tsbuildinfo|*.tmp|*.orig|*.rej|*.iml|*.swp|*.swo|*~)
      return 1 ;;
  esac
  return 0
}

# --- defaults -------------------------------------------------------------
TASKS_ROOT="${TASK_WORKSPACE_ROOT:-}"
TASK=""
PROJECT_OPT=""
MERGE=0
DELETE_BRANCH=0
FORCE=0
CLEAN_STRAY=0
ARCHIVE_DOCS=0
DOCS_DIR=""
TARGET=""
KEEP=()

# --- parse arguments ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)       usage; exit 0 ;;
    --merge)         MERGE=1;        shift ;;
    --no-merge)      MERGE=0;        shift ;;
    --delete-branch) DELETE_BRANCH=1; shift ;;
    --force)         FORCE=1;        shift ;;
    --clean-stray)   CLEAN_STRAY=1;  shift ;;
    --archive-docs)  ARCHIVE_DOCS=1; shift ;;
    --docs-dir)      DOCS_DIR="$2";  ARCHIVE_DOCS=1; shift 2 ;;
    --keep)          KEEP+=("$2");   shift 2 ;;
    --target)        TARGET="$2";    shift 2 ;;
    --project)       PROJECT_OPT="$2"; shift 2 ;;
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
case "$PROJECT_OPT" in
  */*|*\\*|.|..) echo "task-done: --project must be one directory name: $PROJECT_OPT" >&2; exit 1 ;;
esac
if [ -n "$DOCS_DIR" ]; then
  DOCS_DIR="$(to_posix_path "$DOCS_DIR")"
fi
case "$TASK" in
  *..*) echo "task-done: a task name or path must not contain '..': $TASK" >&2; exit 1 ;;
esac
# Accept a native Windows path for the task as well as a POSIX one.
if [[ "$TASK" == [A-Za-z]:* ]]; then
  TASK="$(to_posix_path "$TASK")"
fi

# --- resolve the task directory -------------------------------------------
# A bare name is looked up under the container even when a directory of the same
# name happens to exist in the current directory; only something that is
# clearly a path (absolute, "." / "..", or carrying a backslash) is read as one
# without asking the container first. "<project>/<task>" is read relative to the
# container, and falls back to a relative path only when no such task exists.
ROOT_EXPLICIT=0
if [ -n "$TASKS_ROOT" ]; then
  ROOT_EXPLICIT=1
fi

resolve_task_from_path() {
  local given="$1" parent grandparent
  TASK_DIR="$(cd "$given" && pwd)"
  parent="$(dirname "$TASK_DIR")"
  grandparent="$(dirname "$parent")"
  if [ "$ROOT_EXPLICIT" -eq 0 ]; then
    if [ -f "$parent/README.md" ] && grep -q '^# Worktree Space' "$parent/README.md" 2>/dev/null; then
      TASKS_ROOT="$parent"
    elif [ -f "$grandparent/README.md" ] && grep -q '^# Worktree Space' "$grandparent/README.md" 2>/dev/null; then
      TASKS_ROOT="$grandparent"
    else
      echo "task-done: cannot tell the container root from '$TASK_DIR'; pass --tasks-root" >&2
      exit 1
    fi
  fi
}

case "$TASK" in
  /*|[A-Za-z]:*|*\\*|.|..)
    [ -d "$TASK" ] || {
      echo "task-done: no such task workspace: $TASK" >&2
      exit 1
    }
    resolve_task_from_path "$TASK"
    ;;
  *)
    if [ -z "$TASKS_ROOT" ]; then
      TASKS_ROOT="$(default_tasks_root "$(pwd)")"
    fi
    TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"
    TASKS_ROOT="${TASKS_ROOT%/}"

    chosen=""
    if [ -n "$PROJECT_OPT" ]; then
      [ -d "$TASKS_ROOT/$PROJECT_OPT/$TASK" ] && chosen="$TASKS_ROOT/$PROJECT_OPT/$TASK"
    elif [[ "$TASK" == */* ]]; then
      [ -d "$TASKS_ROOT/$TASK" ] && chosen="$TASKS_ROOT/$TASK"
    else
      matches=()
      [ -d "$TASKS_ROOT/$TASK" ] && matches+=("$TASKS_ROOT/$TASK")
      for candidate in "$TASKS_ROOT"/*/"$TASK"/; do
        [ -d "$candidate" ] && matches+=("${candidate%/}")
      done
      if [ ${#matches[@]} -gt 1 ]; then
        echo "task-done: '$TASK' exists in more than one project; name it as <project>/<task>:" >&2
        for candidate in "${matches[@]}"; do
          echo "  ${candidate#"$TASKS_ROOT"/}" >&2
        done
        exit 1
      fi
      if [ ${#matches[@]} -eq 1 ]; then
        chosen="${matches[0]}"
      fi
    fi

    if [ -n "$chosen" ]; then
      TASK_DIR="$chosen"
    elif [ -d "$TASK" ] && is_task_dir "$TASK"; then
      resolve_task_from_path "$TASK"
    else
      echo "task-done: no such task workspace under $TASKS_ROOT: $TASK" >&2
      echo "  (pass --tasks-root if the container is not in the default location)" >&2
      exit 1
    fi
    ;;
esac

TASKS_ROOT="$(to_posix_path "$TASKS_ROOT")"
TASKS_ROOT="${TASKS_ROOT%/}"
TASK_DIR="$(to_posix_path "$TASK_DIR")"
TASK_NAME="$(basename "$TASK_DIR")"
PROJECT=""

case "$TASK_DIR" in
  "$TASKS_ROOT"/*)
    REL="${TASK_DIR#"$TASKS_ROOT"/}"
    REST="${REL#*/}"
    if [ "$REST" = "$REL" ]; then
      PROJECT=""
    elif [[ "$REST" != */* ]]; then
      PROJECT="${REL%%/*}"
    else
      echo "task-done: not a task space under $TASKS_ROOT: $TASK_DIR" >&2
      exit 1
    fi ;;
  *)
    echo "task-done: $TASK_DIR is not inside the container root $TASKS_ROOT" >&2
    exit 1 ;;
esac

if ! is_task_dir "$TASK_DIR"; then
  echo "task-done: no git worktrees found in $TASK_DIR" >&2
  exit 1
fi

# --- memory sharing (read before the breadcrumb is removed) ---------------
SHARE_MEMORY=0
AGENT=claude
if [ -f "$TASK_DIR/README.md" ] && grep -q 'Share memory: yes' "$TASK_DIR/README.md"; then
  SHARE_MEMORY=1
  AGENT="$(sed -n 's/^- Agent: //p' "$TASK_DIR/README.md" | head -1 | tr -d '`')"
  [ -n "$AGENT" ] || AGENT=claude
fi
HOOK="$(memory_hook_for "$AGENT")"

# --- preflight: every refusal before anything is changed ------------------
HAS_WORKTREES=0
for candidate in "$TASK_DIR"/*/; do
  [ -d "$candidate" ] || continue
  is_linked_worktree "${candidate%/}" && HAS_WORKTREES=1
done

WT_PATHS=()
WT_NAMES=()
WT_BRANCHES=()
WT_MAINS=()
WT_TARGETS=()
PROBLEMS=0

for candidate in "$TASK_DIR"/*/; do
  [ -d "$candidate" ] || continue
  worktree="${candidate%/}"
  is_linked_worktree "$worktree" || continue
  name="$(basename "$worktree")"

  if [ -L "$worktree" ]; then
    echo "== $name" >&2
    echo "  ERROR: this worktree is a link, not a directory; remove it by hand" >&2
    PROBLEMS=1
    continue
  fi

  branch="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    echo "== $name" >&2
    echo "  ERROR: cannot read the branch of $worktree" >&2
    PROBLEMS=1
    continue
  fi
  if [ "$branch" = "HEAD" ]; then
    echo "== $name" >&2
    echo "  ERROR: $worktree is on a detached HEAD, so there is no branch to merge or keep." >&2
    echo "  Check out a branch there (or copy the commits somewhere) and run again." >&2
    PROBLEMS=1
    continue
  fi

  dirty="$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || true)"
  dirty="${dirty:-0}"
  if [ "$dirty" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
    echo "== $name" >&2
    if [ "$MERGE" -eq 1 ] || [ "$DELETE_BRANCH" -ne 1 ]; then
      echo "  ERROR: uncommitted work is waiting in $worktree ($dirty file(s)); commit it before the task can be finished." >&2
      echo "  Or pass --force to discard it." >&2
    else
      echo "  ERROR: uncommitted work is waiting in $worktree ($dirty file(s)), and a dirty worktree cannot be removed." >&2
      echo "  Commit it, or pass --force to discard it together with the branch." >&2
    fi
    PROBLEMS=1
    continue
  fi

  main="$(git -C "$worktree" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  if [ -z "$main" ]; then
    echo "== $name" >&2
    echo "  ERROR: cannot locate the source repository for $name" >&2
    PROBLEMS=1
    continue
  fi

  target=""
  if [ "$MERGE" -eq 1 ]; then
    checked="$(git -C "$main" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    if [ -z "$checked" ]; then
      echo "== $name" >&2
      echo "  ERROR: '$main' has no branch checked out, so there is no branch to merge into." >&2
      echo "  Check out the target branch there and run again." >&2
      PROBLEMS=1
      continue
    fi
    if [ -n "$TARGET" ] && [ "$TARGET" != "$checked" ]; then
      echo "== $name" >&2
      echo "  ERROR: merge target '$TARGET' is not checked out in '$main' (it is on '$checked')." >&2
      echo "  Switch '$main' to '$TARGET' first, or omit --target to merge into '$checked'." >&2
      PROBLEMS=1
      continue
    fi
    target="${TARGET:-$checked}"
    if [ "$target" = "$branch" ]; then
      echo "== $name" >&2
      echo "  ERROR: merge target '$target' is the branch being merged" >&2
      PROBLEMS=1
      continue
    fi
    if ! git -C "$main" show-ref --verify --quiet "refs/heads/$target"; then
      echo "== $name" >&2
      echo "  ERROR: merge target '$target' is not a local branch of '$main'" >&2
      PROBLEMS=1
      continue
    fi
  fi

  WT_PATHS+=("$worktree")
  WT_NAMES+=("$name")
  WT_BRANCHES+=("$branch")
  WT_MAINS+=("$main")
  WT_TARGETS+=("$target")
done

if [ ${#WT_PATHS[@]} -eq 0 ] && [ "$HAS_WORKTREES" -eq 1 ]; then
  echo "task-done: no usable worktrees found in $TASK_DIR" >&2
  exit 1
fi
if [ "$PROBLEMS" -ne 0 ]; then
  echo "task-done: nothing was merged or removed; fix the problems above and run again" >&2
  exit 1
fi
if [ "$HAS_WORKTREES" -eq 0 ]; then
  echo "no worktrees to merge or remove under $TASK_DIR; cleaning what is left"
fi

# --- merge, remove, delete -------------------------------------------------
FAILED=0
for i in "${!WT_PATHS[@]}"; do
  worktree="${WT_PATHS[$i]}"
  name="${WT_NAMES[$i]}"
  branch="${WT_BRANCHES[$i]}"
  main="${WT_MAINS[$i]}"
  target="${WT_TARGETS[$i]}"

  echo "== $name (branch: $branch)"

  if [ "$MERGE" -eq 1 ]; then
    if ! merge_out="$(git -C "$main" merge --no-ff --no-edit "$branch" 2>&1)"; then
      git -C "$main" merge --abort >/dev/null 2>&1 || true
      if printf '%s\n' "$merge_out" | grep -qi 'would be overwritten by merge\|local changes'; then
        echo "  ERROR: '$main' has uncommitted changes that this merge would overwrite;" >&2
        echo "  commit or stash them in '$main' and run again (worktree and branch kept)" >&2
      else
        echo "  ERROR: merging '$branch' into '$target' failed (conflict?); worktree and branch kept" >&2
      fi
      FAILED=1
      continue
    fi
    if printf '%s\n' "$merge_out" | grep -qi 'already up to date'; then
      echo "  '$branch' had no commits that '$target' did not already contain"
    else
      echo "  merged '$branch' -> '$target' (--no-ff)"
    fi
  fi

  wt_flags=()
  if [ "$FORCE" -eq 1 ]; then
    wt_flags+=(--force)
  fi
  if ! git -C "$main" worktree remove "${wt_flags[@]}" "$worktree"; then
    echo "  ERROR: failed to remove worktree (uncommitted changes? use --force)" >&2
    FAILED=1
    continue
  fi
  echo "  worktree removed"

  if [ "$SHARE_MEMORY" -eq 1 ] && [ -f "$HOOK" ]; then
    bash "$HOOK" unlink "$worktree" >/dev/null 2>&1 || true
  fi

  if [ "$DELETE_BRANCH" -eq 1 ]; then
    if [ "$FORCE" -eq 1 ]; then
      if git -C "$main" branch -D -- "$branch" >/dev/null 2>&1; then
        echo "  branch '$branch' deleted"
      else
        echo "  WARN: branch '$branch' not deleted" >&2
      fi
    elif git -C "$main" branch -d -- "$branch" >/dev/null 2>&1; then
      echo "  branch '$branch' deleted"
    else
      echo "  WARN: branch '$branch' not deleted (not merged?)" >&2
    fi
  else
    echo "  branch '$branch' kept"
  fi
done

# A worktree kept by a failure still holds its `.git` pointer; the task
# directory is left exactly as it stands, so a second run can pick it up.
REMAIN=0
for candidate in "$TASK_DIR"/*/; do
  [ -d "$candidate" ] || continue
  is_linked_worktree "${candidate%/}" && REMAIN=$((REMAIN + 1))
done

if [ "$REMAIN" -gt 0 ]; then
  echo "note: the task directory is kept; $REMAIN worktree(s) are still in it: $TASK_DIR"
  [ "$FAILED" -eq 1 ] && exit 1
  exit 0
fi

# --- clean up the task directory ------------------------------------------
# The breadcrumb stays until the directory itself goes, so a directory left
# behind with stray files is still recognisable as a task space (and a second
# run can clean it).

if [ "$ARCHIVE_DOCS" -eq 1 ]; then
  if [ -n "$DOCS_DIR" ]; then
    docs_dir="$DOCS_DIR"
  elif [ -n "$PROJECT" ]; then
    docs_dir="$TASKS_ROOT/archived-docs/$PROJECT/$TASK_NAME-$(date +%Y%m%d-%H%M%S)"
  else
    docs_dir="$TASKS_ROOT/archived-docs/$TASK_NAME-$(date +%Y%m%d-%H%M%S)"
  fi
  # The archive must live outside the task directory, or the files moved there
  # would be deleted moments later when the container is removed.
  case "$docs_dir/" in
    "$TASK_DIR/"*)
      echo "task-done: --docs-dir must be outside the task directory: $docs_dir" >&2
      exit 1 ;;
  esac
fi

STRAY=()
kept=()
while IFS= read -r -d '' leftover; do
  [ -e "$leftover/.git" ] && continue   # kept worktree
  [ "$(basename "$leftover")" = "README.md" ] && continue   # the breadcrumb
  STRAY+=("$leftover")
done < <(find "$TASK_DIR" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

if [ ${#STRAY[@]} -gt 0 ]; then
  for s in "${STRAY[@]}"; do
    name="$(basename "$s")"
    # The plugin's own bookkeeping (a task created by dsh-worktree-space and
    # finished here) is not the user's writing: it goes with the space, and it
    # is not filed into the documents archive.
    if [ "$name" = ".worktree-space" ]; then
      if require_direct_child "$TASK_DIR" "$s" && require_real_dir "$s"; then
        rm -rf -- "$s"
      fi
      continue
    fi
    keep=0
    for k in "${KEEP[@]}"; do
      [ "$k" = "$name" ] && keep=1
    done
    if [ "$keep" -eq 1 ]; then
      kept+=("$s")
      continue
    fi

    if [ "$CLEAN_STRAY" -eq 1 ] || [ "$ARCHIVE_DOCS" -eq 1 ]; then
      require_direct_child "$TASK_DIR" "$s" || { kept+=("$s"); continue; }
      require_real_dir "$s" || { kept+=("$s"); continue; }
      is_dir=0
      [ -d "$s" ] && is_dir=1
      if [ "$ARCHIVE_DOCS" -eq 1 ] && stray_is_content "$name" "$is_dir"; then
        if mkdir -p "$docs_dir" && cp -r -- "$s" "$docs_dir/"; then
          rm -rf -- "$s"
          echo "  archived: $name -> $docs_dir/"
        else
          kept+=("$s")
          echo "  WARN: could not archive '$name'; kept in place" >&2
        fi
      else
        rm -rf -- "$s" || true
        echo "  removed: $name"
      fi
    else
      kept+=("$s")
    fi
  done
  if [ ${#kept[@]} -gt 0 ]; then
    echo "  stray files kept:"
    for s in "${kept[@]}"; do echo "    - $s"; done
  fi
fi

if [ ${#kept[@]} -eq 0 ]; then
  rm -f -- "$TASK_DIR/README.md"
  if rmdir "$TASK_DIR" 2>/dev/null; then
    echo "task directory removed: $TASK_DIR"
    if [ -n "$PROJECT" ] && require_direct_child "$TASKS_ROOT" "$TASKS_ROOT/$PROJECT"; then
      rmdir "$TASKS_ROOT/$PROJECT" 2>/dev/null || true
    fi
  else
    echo "note: task directory kept (something is still in it): $TASK_DIR"
  fi
else
  echo "note: task directory kept (stray files still present): $TASK_DIR"
  echo "  run again with --clean-stray to remove them, or delete them by hand"
fi

if [ "$FAILED" -eq 1 ]; then
  echo "task-done: finished with errors (see above)" >&2
  exit 1
fi
echo "task-done: complete"