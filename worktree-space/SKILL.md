---
name: worktree-space
description: Create and finish isolated per-task git worktree workspaces that span one or more repositories under a source root, keeping the task container in a separate directory outside the source tree. Use whenever the user wants to start a new task or feature in a single- or multi-repo workspace, asks to set up or clean up a task workspace, wants agent sessions isolated from each other via git worktrees so commits never mix, or needs to merge and remove a finished task. When creating a task, ask the user where the task container should live (recommend a drive-root folder such as E:\worktree-space). Provides task-new / task-done / task-list / suggest-tasks-root scripts.
---

# Worktree Space

Isolate work per task using git worktrees, in a source root that holds one or
more git repositories side by side. One task is one plain directory holding a
worktree of every relevant repository, all on the same branch, so a single
session can edit across repositories while other sessions (and the source
repositories themselves) stay untouched.

**This skill does two things: create a task space, and finish it.** Listing and
the container-location recommendation are helpers for those two. It does not
open, watch, or message agent sessions, and it does not deploy anything - a
plain skill has no session or panel to do that from. If you need those, that is
a different tool, not a missing flag here.

## The model

```
E:\workspace\public\projects\       ← source root: the repositories, read-only, stay on main
├── project_a\                      ← a repository, stays on main
└── project_b\                      ← a repository, stays on main

E:\worktree-space\                  ← container root: lives OUTSIDE the source tree
└── projects\                       ← project layer: the source root's own directory name
    └── fix-login\                  ← task directory — the session's cwd
        ├── project_a\              ← worktree, branch task/fix-login
        └── project_b\              ← worktree, branch task/fix-login
```

The project layer is what keeps two projects' tasks of the same name apart, and
it is the same depth in every case, so the task directory is always
`<container root>/<project>/<task>`.

For a single repository the shape is the same: the source root is that one
repository and the task directory holds a single worktree of it. Where the
source root **is** the repository, the project layer and the repository take the
same name — `E:\workspace\repo-x` gives `<container>/repo-x/<task>/repo-x` — and
that repeat is deliberate, not a mistake to correct.

Why this shape:

- **File isolation** — each task directory is a physically separate checkout;
  sessions can never overwrite each other's uncommitted work.
- **Commit isolation** — every worktree is on its own branch (`task/<task>`),
  so commits from different tasks can never interleave on the same branch.
- **Cross-repo coherence** — all repositories in a task share the same branch
  name, which is what links the task's commits across repos.
- **Project separation** — tasks of the same name under different source roots
  do not collide, because each source root files its tasks under its own name.
- **Source/work separation** — the container is a directory of its own, never
  created inside the source root or inside any other repository; the scripts
  reject nested layouts, a container that is itself a git repository, and a
  container inside one.
- **Merge control** — merging into a branch only happens through
  `task-done.sh`, when the user asks for it; nobody hand-merges into `main`.

The container is the scripts' own zone: creating a task writes a `README.md`
there saying so, unless one is already present. Do not `git init` or clone into
it.

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
     source must stay isolated; the script refuses nested layouts and a
     container that is, or is inside, a git repository.
5. **Base (start point)** — ask which commit the new branches start from
   (AskUserQuestion). Recommend the **current HEAD of each repository**
   (the default — omit `--base`). Alternatives: another active branch
   (find with `git -C <repo> branch --sort=-committerdate`) or the main
   branch (`main` / `master`). Only pass `--base <ref>` when the user picks
   a specific ref; the same ref is applied to every repository.
6. **Create it**:
   `bash <skill-dir>/scripts/task-new.sh <task> [repos...] --src <source-root> --tasks-root <chosen-location> [--base <ref>]`
7. **Report** to the user: the task directory path
   (`<container>/<project>/<task>`), the project layer, and the branch name
   (`task/<task>`).

Details of `task-new.sh`:

- The task directory is `<container root>/<project>/<task>`; the project is the
  source root's own directory name, derived rather than asked for.
- Without repo arguments it discovers the source repositories: if the source
  root is itself a git repository it is used directly; otherwise every
  top-level subdirectory whose `.git` is a real directory is used (worktree
  checkouts and `*.worktrees` folders are skipped).
- With repo arguments it creates worktrees for only those repositories.
- The new branch starts from each repository's current HEAD by default;
  pass `--base <ref>` to start from a specific commit/branch instead. The
  prefix is `task/` unless `--prefix` / `TASK_BRANCH_PREFIX` says otherwise.
- The task name becomes both a directory and a branch suffix, so it is refused
  when it cannot survive both: `/`, `\`, whitespace, `~ ^ : ? * [ ]`, a
  trailing dot or space, `.` / `..`, `..` anywhere, `@{`, a trailing `.lock`,
  or a Windows reserved device name (`CON`, `NUL`, `COM1`, ...). The check
  runs before anything is created.
- If creating a later repository fails, the script **rolls back** the
  worktrees, branches and directories this run made, so the same name can be
  used again. Anything it could not remove is named; nothing that existed
  before is touched.
- It writes a `README.md` into the task directory recording the task name,
  project, branch, base, repositories, and the conventions below, so the
  session has the rules in front of it.
- `--share-memory` shares each worktree's auto-memory with the source root via
  the agent's memory hook (see `--agent` below); off by default. See "Sharing
  auto-memory" below.
- `--agent <name>` selects which agent's memory hook `--share-memory` uses
  (default `claude`, or `$TASK_WORKSPACE_AGENT`). The scripts themselves are
  agent-agnostic.
- By default the new branch is **local-only** (no upstream). `--push` pushes it
  to `origin` and sets upstream tracking — only pass it when the user explicitly
  asks to create/associate a remote branch; do not prompt for it otherwise. A
  rollback removes the local branch only: a branch already pushed stays on the
  remote and has to be deleted there. If the push fails, the branch stays local
  and the create still succeeds, with a warning.

## Working inside a task workspace

When your session's working directory is a task directory (a folder whose
subfolders are git worktrees of different repositories), apply these rules:

- The task directory itself is **not** a git repo — run git commands inside
  each repository subdirectory.
- Commit in **each repository separately**; there is no single cross-repo
  commit. Same branch name everywhere (`task/<task>` by default,
  `<prefix><task>` when `--prefix` was given).
- **Never edit, commit, or merge in the source repositories** — they are
  read-only references. Only the task directory is yours.
- **Never hand-merge into `main`/`master`.** Finishing is `task-done.sh`, and
  whether a task is finished — and whether its branch lands — is the user's
  decision; run the script when they ask for it.
- If another session or process created the task workspace, follow the
  `README.md` inside it instead of creating a new one.

## Sharing auto-memory across workspaces (optional)

Each agent stores memory differently, and only Claude Code keys auto-memory by
working directory. `--share-memory` delegates to a pluggable per-agent "memory
hook" (`adapters/claude.sh` for the junction, `adapters/noop.sh` for the rest)
so worktree sessions share the source session's memory:

| agent | memory location | hook behaviour |
| ----- | --------------- | -------------- |
| `claude` | `~/.claude/projects/<encoded-cwd>/memory` (per-directory) | creates a directory junction |
| `opencode` | in-repo `AGENTS.md` / `CLAUDE.md` | no-op (already shared) |
| `dsh` | `$DSH_HOME/AGENTS.md` + in-repo `AGENTS.md` | no-op (already shared) |
| `codex` | `~/.codex/` (global) + in-repo `AGENTS.md` | no-op (already shared) |

```bash
bash <skill-dir>/scripts/task-new.sh <task> --share-memory --agent claude \
  --src <source-root> --tasks-root <tasks-root>
```

Only `claude` needs a junction; the other three read `AGENTS.md`/global state
that already travels with (or is shared by) every worktree, so their hooks do
nothing. `task-done.sh` runs the same hook's `unlink` when finishing; the shared
memory itself is never deleted.

Caveats:

- The `claude` hook relies on Claude Code's **undocumented** per-project layout
  (`~/.claude/projects/<encoded-cwd>/memory`); if that layout or its path
  encoding changes, sharing silently stops working.
- The `claude` junction is Windows-only (via PowerShell); the no-op hooks work
  anywhere.
- Prefer putting genuinely project-shared facts in the repo's `AGENTS.md` /
  `CLAUDE.md`, which follow every worktree automatically and need no mechanism.

## Finishing a task

When the user asks to finish or clean up a task, run:

```bash
bash <skill-dir>/scripts/task-done.sh <project>/<task> --tasks-root <tasks-root>
```

By default this **removes the worktrees, keeps the branches, and keeps any
stray files** in the task directory — it does not merge, delete a branch, or
delete stray files unless the user explicitly asked. Confirm each destructive
step with the user (AskUserQuestion) before running the script:

1. **Merge?** Default no. Only when the user explicitly says to merge, pass
   `--merge`. The merge target is **the branch the source repository has
   checked out**, because that is the only branch the script can merge into
   without moving somebody else's checkout. `--target <branch>` is accepted
   only when it is that branch; if the source repository is on another branch
   (or detached), the script refuses and asks the user to switch it first.
2. **Delete branch?** Default no. Only when the user explicitly says to
   delete the branch, and only after it has been merged, pass
   `--delete-branch` (requires `--merge`).
3. **Stray files?** List the task directory's top-level entries; anything that
   is not a worktree (a folder with a `.git` file) and not the `README.md`
   breadcrumb is a stray file. Build output and editor state (`.idea`,
   `node_modules`, `dist`, ...) are disposable; the rest is the user's own
   documents (plans/notes). If there are documents, offer to archive them:
   pass `--archive-docs` to file them under
   `archived-docs/<project>/<task>-<timestamp>/` in the container root (this
   also removes the disposable junk); add `--keep <name>` for any entry the
   user wants left in place.

Every worktree readiness check runs **before anything is changed**. The finish
refuses, with nothing merged and nothing removed, when:

- a worktree has uncommitted work (commit it, or pass `--force` to discard it);
- a worktree is on a detached HEAD (there is no branch to merge or keep);
- `--merge` was asked for and the source repository is detached, or is on a
  branch other than the one named by `--target`;
- a worktree cannot be read.

Fix the problem and run again; the second run starts from the same state.

One refusal can only happen once a merge is attempted: a source repository whose
own checkout has changes the merge would overwrite. Git is the only thing that
knows which files a merge touches, so that repository's merge is aborted and its
worktree kept — but a repository processed before it may already be finished.
Commit or stash the source checkout and run again.

Examples:

```bash
# just clean up, keep the branch (default)
bash <skill-dir>/scripts/task-done.sh <project>/<task> --tasks-root <tasks-root>

# merge into the branch the source repository is on, then delete the branch
bash <skill-dir>/scripts/task-done.sh <project>/<task> --tasks-root <tasks-root> \
  --merge --delete-branch

# a bare task name that exists under more than one project
bash <skill-dir>/scripts/task-done.sh <task> --project <project> --tasks-root <tasks-root>
```

Details:

- `<task>`, `<project>/<task>`, a directory path, and `.` from inside the task
  directory all work. A path needs no `--tasks-root` when the container carries a
  container README (this skill's or the plugin's); otherwise pass it. The layout
  from before the project layer (`<container>/<task>`) is still read and finished,
  and archives from it keep the old `<task>-<timestamp>` destination.
- On a merge conflict it aborts the merge and keeps that worktree and branch
  for manual handling; other repositories still complete.
- Stray files left in the task directory are kept by default and listed.
  `--clean-stray` removes them (except `--keep` entries). `--archive-docs`
  files the user's own documents into the archive root and removes the rest;
  `--docs-dir <dir>` overrides the destination and implies `--archive-docs`. A
  worktree kept on failure is left untouched.
- `--no-merge` is an explicit alias for the default (no merge).
- `--delete-branch` uses `git branch -d` (safe: refuses an unmerged branch)
  unless `--force` is also given; when git refuses, the branch is kept and a
  warning is printed.
- `--clean-stray` deletes the stray files, and `--force` discards uncommitted
  work and force-deletes the branch when `--delete-branch` is also given — both
  destructive, only pass them when the user explicitly said so. The plain skill
  has no panel to fall back on, so the flags stay available; it is the caller's
  job to use them deliberately.
- `--project <name>` picks the project layer when a bare task name exists under
  more than one project; naming `<project>/<task>` does the same.
- If stray files are kept and every worktree is gone, the breadcrumb stays and
  the directory is still recognised as a task space: a second run with
  `--clean-stray` removes what is left.

## Listing tasks

```bash
bash <skill-dir>/scripts/task-list.sh --tasks-root <tasks-root>
```

Shows each task as `<project>/<task>` (a task from the pre-project-layer layout
prints as `<task>`), its worktrees, their branches, and how many dirty files
each has. It reads both layouts, and prints `detached` rather than `HEAD` for a
checkout with no branch.

## Configuration

All scripts accept explicit flags and read these environment variables
(flags win):

| Variable               | Default                          | Meaning              |
| ---------------------- | -------------------------------- | -------------------- |
| `TASK_WORKSPACE_SRC`   | current directory                | source root          |
| `TASK_WORKSPACE_ROOT`  | drive-root recommendation        | task container root  |
| `TASK_BRANCH_PREFIX`   | `task/`                          | branch prefix        |

Windows paths are accepted in both `E:\...` and `/e/...` forms. Scripts run
under bash (Git Bash on Windows).

## Failure modes worth knowing

- Nested layouts are rejected: the container must not be the source root,
  inside it, or contain it.
- The container must not be a git repository itself, or sit inside one.
- `task-new` refuses if the task directory or the branch already exists in any
  repository — pick another task name.
- `task-new` refuses if `--base <ref>` does not resolve in any repository.
- A failure while creating rolls back the worktrees, branches and directories
  that run made; what could not be removed is named.
- `task-done` refuses (before changing anything) on uncommitted work, a
  detached HEAD, or a merge target the source repository is not on.
- `git worktree remove` still refuses a dirty worktree without `--force`; the
  preflight catches that earlier and says which repository and how many files.
- Task names must not contain `/`, `\`, whitespace, or the characters git
  refuses in a branch — they become branch names.

## Relation to the dsh-worktree-space plugin

The DSH plugin uses the same `<container>/<project>/<task>` layout and the same
`task/` branch prefix, so the two can share a container. Their bookkeeping
differs: the plugin writes `.worktree-space/worktree-space.json` and opens a
session for the task; this skill writes a `README.md` breadcrumb and leaves the
session to the user. The plugin also deploys and watches sessions; a plain skill
cannot, so none of that is described here.