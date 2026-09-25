---
name: task-workspace
description: Create and manage isolated per-task git worktree workspaces that span one or more repositories under a source root, keeping the task container in a separate directory outside the source tree. Use whenever the user wants to start a new task or feature in a single- or multi-repo workspace, asks to set up or clean up a task workspace / session workspace, wants agent sessions isolated from each other via git worktrees so commits never mix, or needs to merge and remove a finished task. When creating a task, ask the user where the task container should live (recommend a drive-root folder such as E:\worktree-space). Provides task-new / task-done / task-list / suggest-tasks-root scripts.
---

# Task Workspace

Isolate agent sessions per task using git worktrees, in a workspace root that
contains one or more git repositories side by side. One task = one plain directory
holding a worktree of every relevant repository, all on the same branch, so a
single agent session can edit across repositories while other sessions (and
the source repositories themselves) stay untouched.

## The model

```
E:\workspace\public\projects\       ← source root: the repositories, read-only, stay on main
├── project_a\                      ← a repository, stays on main
└── project_b\                      ← a repository, stays on main

E:\worktree-space\                  ← task container: lives OUTSIDE the source tree
└── fix-login\                      ← task directory — the agent session's cwd
    ├── project_a\                  ← worktree, branch feat/fix-login
    └── project_b\                  ← worktree, branch feat/fix-login
```

For a single repository the shape is the same: the source root is that one
repository and the task directory holds a single worktree of it.

Why this shape:

- **File isolation** — each task directory is a physically separate checkout;
  sessions can never overwrite each other's uncommitted work.
- **Commit isolation** — every worktree is on its own branch (`feat/<task>`),
  so commits from different tasks can never interleave on the same branch.
- **Cross-repo coherence** — all repositories in a task share the same branch
  name, which is what links the task's commits across repos.
- **Source/work separation** — the task container is a directory of its own,
  never created inside the source root; the scripts reject nested layouts.
- **Merge control** — merging into the default branch only happens through
  `task-done.sh`, run on the user's request after review; agents never merge.

## Starting a task (ask first, then create)

When the user asks to create a task workspace, follow this flow — do not run
`task-new.sh` silently with guessed locations:

1. **Task name** — take it from the user's message; ask if it is missing.
2. **Source root** — the directory containing the repositories, usually the
   user's current directory. If the current directory is itself a single git
   repository (`.git` is a real directory), use it directly. A git worktree
   checkout (its `.git` is a file) is NOT a source root — ascend to the real
   one. Ask the user when it is ambiguous.
3. **Recommended container location** — compute it:
   `bash <skill-dir>/scripts/suggest-tasks-root.sh <source-root>`
   This recommends a folder directly under the drive root of the source
   root, e.g. `E:\workspace` when free, otherwise `E:\worktree-space`
   (reused if it already exists).
4. **Ask the user** where the task container should live (AskUserQuestion):
   - First option: the recommendation from step 3, labeled `(推荐)`.
   - One or two alternatives, e.g. another drive or a differently named
     folder on the same drive; the user can type their own via "Other".
   - Skip the question only when `TASK_WORKSPACE_ROOT` is set (use it
     directly) or the user already stated the location.
   - Never offer (or accept) a location inside the source root — work and
     source must stay isolated; the script refuses nested layouts.
5. **Base (start point)** — ask which commit the new branches start from
   (AskUserQuestion). Recommend the **current HEAD of each repository**
   (the default — omit `--base`). Alternatives: another active branch
   (find with `git -C <repo> branch --sort=-committerdate`) or the main
   branch (`main` / `master`). Only pass `--base <ref>` when the user picks
   a specific ref; the same ref is applied to every repository.
6. **Create it**:
   `bash <skill-dir>/scripts/task-new.sh <task> [repos...] --src <source-root> --tasks-root <chosen-location> [--base <ref>]`
7. **Report** to the user: the workspace is ready (the task directory
   path), plus the branch name (`feat/<task>`).

Details of `task-new.sh`:

- Without repo arguments it discovers the source repositories: if the source
  root is itself a git repository it is used directly; otherwise every
  top-level subdirectory whose `.git` is a real directory is used (worktree
  checkouts and `*.worktrees` folders are skipped).
- With repo arguments it creates worktrees for only those repositories.
- The new branch starts from each repository's current HEAD by default;
  pass `--base <ref>` to start from a specific commit/branch instead.
- It writes a `README.md` into the task directory recording the task name,
  branch, base, repositories, and the conventions below, so the session has
  the rules in front of it.

## Working inside a task workspace

When your session's working directory is a task directory (a folder whose
subfolders are git worktrees of different repositories), apply these rules:

- The task directory itself is **not** a git repo — run git commands inside
  each repository subdirectory.
- Commit in **each repository separately**; there is no single cross-repo
  commit. Same branch name everywhere (`feat/<task>`).
- **Never edit, commit, or merge in the source repositories** — they are
  read-only references. Only the task directory is yours.
- **Never merge into main/master** from a session. Finishing the task is the
  user's action (below).
- If another session or process created the task workspace, follow the
  `README.md` inside it instead of creating a new one.

## Finishing a task

When the user asks to finish or clean up a task, run:

```bash
bash <skill-dir>/scripts/task-done.sh <task-name> --tasks-root <tasks-root>
```

By default this **removes the worktrees, empties the task directory of stray
files, and keeps the branches** — it does not merge and does not delete a
branch unless the user explicitly asked for those. Merging and branch
deletion are separate, explicit steps; confirm each with the user
(AskUserQuestion) before running the script:

1. **Merge?** Default no. Only when the user explicitly says to merge, pass
   `--merge`. When merging, ask which target branch to merge into and pass
   `--target <branch>` (if omitted, auto-detected: `origin/HEAD`, then
   `main`, then `master`).
2. **Delete branch?** Default no. Only when the user explicitly says to
   delete the branch, and only after it has been merged, pass
   `--delete-branch` (requires `--merge`).

Examples:

```bash
# just clean up, keep the branch (default)
bash <skill-dir>/scripts/task-done.sh <task-name> --tasks-root <tasks-root>

# merge into main, then delete the branch
bash <skill-dir>/scripts/task-done.sh <task-name> --tasks-root <tasks-root> \
  --merge --target main --delete-branch
```

Details:

- A directory path also works for `<task>` (including `.` from inside the
  task directory), in which case `--tasks-root` is unnecessary.
- The merge target is auto-detected (`origin/HEAD`, then `main`, then
  `master`); override with `--target <branch>`.
- On a merge conflict it aborts the merge and keeps that worktree and branch
  for manual handling; other repositories still complete.
- Stray files left in the task directory (e.g. `.idea`, editor caches) are
  removed; a worktree kept on failure is left untouched.
- `--no-merge` is an explicit alias for the default (no merge).
- `--delete-branch` uses `git branch -d` (safe: refuses an unmerged branch)
  unless `--force` is also given.
- `--force` removes dirty worktrees and force-deletes branches — destructive,
  only use it deliberately.

## Listing tasks

```bash
bash <skill-dir>/scripts/task-list.sh --tasks-root <tasks-root>
```

Shows each task directory, its worktrees, their branches, and how many dirty
files each has.

## Configuration

All scripts accept explicit flags and read these environment variables
(flags win):

| Variable               | Default                          | Meaning              |
| ---------------------- | -------------------------------- | -------------------- |
| `TASK_WORKSPACE_SRC`   | current directory                | source root          |
| `TASK_WORKSPACE_ROOT`  | drive-root recommendation        | task container root  |
| `TASK_BRANCH_PREFIX`   | `feat/`                          | branch prefix        |

Windows paths are accepted in both `E:\...` and `/e/...` forms. Scripts run
under bash (Git Bash on Windows).

## Failure modes worth knowing

- Nested layouts are rejected: the task container must not be the source
  root, inside it, or contain it. Propose a location outside the source tree.
- `task-new` refuses if the task directory or the branch already exists in
  any repository — pick another task name.
- `task-new` refuses if `--base <ref>` does not resolve in any repository.
- `git worktree remove` refuses when a worktree has uncommitted changes;
  `task-done` surfaces that error and keeps the worktree so nothing is lost.
- Task names must not contain `/`, `\`, or whitespace (they become branch
  names).
