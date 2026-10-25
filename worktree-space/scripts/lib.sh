#!/usr/bin/env bash
# Shared helpers for the worktree-space scripts.

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
  local src="$1" tasks_root="$2" src_cmp root_cmp
  # Win32 compares paths case-insensitively, so a spelling that differs only in
  # case must not slip past the nesting check.
  src_cmp="$src"
  root_cmp="$tasks_root"
  if is_windows; then
    src_cmp="${src,,}"
    root_cmp="${tasks_root,,}"
  fi
  if [ "$src_cmp" = "$root_cmp" ]; then
    echo "error: tasks root must not be the source root itself: $src" >&2
    return 1
  fi
  case "$root_cmp/" in
    "$src_cmp"/*)
      echo "error: tasks root is inside the source root: $tasks_root" >&2
      echo "  work and source must be isolated; pick a location outside the source tree" >&2
      return 1 ;;
  esac
  case "$src_cmp/" in
    "$root_cmp"/*)
      echo "error: source root is inside the tasks root: $tasks_root" >&2
      echo "  work and source must be isolated; pick a location outside the source tree" >&2
      return 1 ;;
  esac
  return 0
}

# --- layout ----------------------------------------------------------------
# A task space is <container root>/<project>/<task>. The project layer is the
# source root's own directory name, so two projects can both hold a task named
# "hotfix" without colliding. The depth is the same in every case, which is what
# lets every script find the three levels without extra metadata.

# The project layer a source root contributes.
project_name_for() {
  basename -- "$1"
}

# The problem with a task name, or an empty string when it is usable.
#
# The name becomes a directory segment inside the container AND the suffix of a
# branch in every repository, so it has to survive both. This is the union of
# what each of them refuses, plus the names Win32 folds onto another name: a
# trailing dot or space, a device name, and the two relative names. Those are not
# cosmetic - "login." and "login" are two accepted names that resolve to one
# directory, and finishing the first would then remove the second.
task_name_problem() {
  local name="$1" lower
  if [ -z "$name" ]; then
    printf 'a task name is required'
    return 0
  fi
  case "$name" in
    .|..) printf "task name must not be '.' or '..': %s" "$name"; return 0 ;;
  esac
  case "$name" in
    *.) printf 'task name must not end with a dot: %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *' ') printf 'task name must not end with a space: %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *[[:space:]]*) printf 'task name must not contain whitespace: %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *[/\\]*) printf 'task name must not contain / or \\: %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *'~'*|*'^'*|*':'*|*'?'*|*'*'*|*'['*|*']'*) printf 'task name must not contain a character git refuses in a branch name ( ~ ^ : ? * [ ] ): %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *[[:cntrl:]]*) printf 'task name must not contain a control character: %s' "$name"; return 0 ;;
  esac
  case "$name" in
    *..*) printf "task name must not contain '..': %s" "$name"; return 0 ;;
  esac
  case "$name" in
    *'@{'*) printf "task name must not contain '@{': %s" "$name"; return 0 ;;
  esac
  case "$name" in
    *.lock) printf "task name must not end with '.lock': %s" "$name"; return 0 ;;
  esac
  lower="${name,,}"
  case "$lower" in
    con|con.*|prn|prn.*|aux|aux.*|nul|nul.*|com[1-9]|com[1-9].*|lpt[1-9]|lpt[1-9].*)
      printf 'task name must not be a Windows reserved device name: %s' "$name"; return 0 ;;
  esac
  return 0
}

require_valid_task_name() {
  local problem
  problem="$(task_name_problem "$1")"
  if [ -n "$problem" ]; then
    echo "error: $problem" >&2
    return 1
  fi
  return 0
}

# The problem with a container root, or an empty string when it is usable.
#
# Two refusals, both about what the container must never be: a git repository
# itself (task spaces would sit on top of version control), or a directory inside
# one (the task space would be committed into the user's repository). The second
# asks the nearest existing ancestor, because the container usually does not
# exist yet when it is first asked about.
container_problem() {
  local root="$1" probe parent top
  if [ -e "$root/.git" ]; then
    printf 'the container root is itself a git repository: %s' "$root"
    return 0
  fi
  probe="$root"
  while [ ! -d "$probe" ]; do
    parent="$(dirname -- "$probe")"
    [ "$parent" = "$probe" ] && break
    probe="$parent"
  done
  top="$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    printf 'the container root is inside a git repository (%s): %s' "$top" "$root"
    return 0
  fi
  return 0
}

require_container_ok() {
  local problem
  problem="$(container_problem "$1")"
  if [ -n "$problem" ]; then
    echo "error: $problem" >&2
    return 1
  fi
  return 0
}

# Say what the container is, once, without overwriting anything already there.
ensure_container_readme() {
  local root="$1"
  local file="$root/README.md"
  [ -f "$file" ] && return 0
  cat > "$file" <<'EOF'
# Worktree Space container

This directory holds one task space per task, filed under a project layer:

    <container root>/<project>/<task>/

Each task directory holds a git worktree of every repository that task touches,
all on one branch. The source repositories live elsewhere and stay untouched.

Do not `git init` or clone into this directory, and do not edit files here by
hand: the scripts in the `worktree-space` skill own this layout. Task spaces are
created with `task-new.sh` and cleared with `task-done.sh`.
EOF
}

# Is this directory a linked worktree? A linked worktree's `.git` is a file
# pointing at the source repository; a normal checkout's `.git` is a directory.
is_linked_worktree() {
  [ -f "$1/.git" ]
}

# Is this directory a task space? It holds at least one linked worktree, or the
# breadcrumb task-new leaves behind. The breadcrumb matters after a finish that
# kept stray files: the worktrees are gone, but the directory is still a task
# space waiting to be cleaned, and a second run has to be able to recognise it.
is_task_dir() {
  local dir="$1" child
  if [ -f "$dir/README.md" ] && head -1 "$dir/README.md" 2>/dev/null | grep -q '^# Task: '; then
    return 0
  fi
  for child in "$dir"/*/; do
    [ -d "$child" ] || continue
    is_linked_worktree "${child%/}" && return 0
  done
  return 1
}

# Refuse to remove anything but a direct child of a known directory. Every
# recursive removal in these scripts goes through this first: the paths are
# built from validated names, and this is the assertion on the result rather
# than on the inputs.
require_direct_child() {
  local parent="$1" target="$2" name
  name="$(basename -- "$target")"
  if [ "$(dirname -- "$target")" != "$parent" ] || [ -z "$name" ] || [ "$name" = "." ] || [ "$name" = ".." ]; then
    echo "refusing to remove outside $parent: $target" >&2
    return 1
  fi
  return 0
}

# Refuse a removal that would follow a link. A junction or symlink sitting in a
# task space is a name for somewhere else, and walking through it would delete
# files this script never created.
require_real_dir() {
  local target="$1"
  if [ -L "$target" ]; then
    echo "refusing to remove a link, not a directory: $target" >&2
    return 1
  fi
  return 0
}

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- agent adapters ---------------------------------------------------------
# The scripts are agent-agnostic; the one agent-specific concern is how an
# agent's auto-memory is shared across worktrees, which is delegated to a
# pluggable "memory hook": an executable implementing two subcommands:
#   hook link   <worktree-posix> <source-posix>
#   hook unlink <worktree-posix>
# Hooks live flat in <skill>/adapters/: claude.sh (junction) and noop.sh (for
# agents whose memory is in-repo or global, so nothing to link).
ADAPTERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/adapters"

# Path of the memory hook for an agent (default: claude).
memory_hook_for() {
  case "$1" in
    claude)          printf '%s/claude.sh' "$ADAPTERS_DIR" ;;
    opencode|dsh|codex) printf '%s/noop.sh' "$ADAPTERS_DIR" ;;
    *)               printf '%s/%s.sh' "$ADAPTERS_DIR" "$1" ;;
  esac
}