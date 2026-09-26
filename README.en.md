# Agent Skills

A collection of reusable [Claude Code](https://claude.com/claude-code) skills. Each
skill lives in its own top-level directory as a self-contained `SKILL.md` (plus any
helper scripts it needs), following the same layout as the official
[`anthropics/skills`](https://github.com/anthropics/skills) repository.

> 中文版：[README.md](README.md)

## Skills

| Skill | Description |
| ----- | ----------- |
| [task-worktree-space](task-worktree-space/SKILL.md) | Create and manage isolated per-task git worktree workspaces that span multiple repositories under a source root. |

## Install

Copy (or symlink) the skill folder you want into your personal skills directory:

```bash
# Linux / macOS
cp -r task-worktree-space ~/.claude/skills/

# Windows (Git Bash)
cp -r task-worktree-space "$USERPROFILE/.claude/skills/"
```

Or symlink it so you always get updates when you pull this repo:

```bash
ln -s "$PWD/task-worktree-space" ~/.claude/skills/task-worktree-space
```

Restart Claude Code (or start a new session) and the skill will be available.

## Usage

Each skill documents its own usage inside its `SKILL.md`. For `task-worktree-space`, the
entry points are the scripts under `task-worktree-space/scripts/`:

- `task-new.sh` — create a task workspace
- `task-done.sh` — clean up / merge a finished task
- `task-list.sh` — list existing tasks
- `suggest-tasks-root.sh` — recommend where to put the task container

### Using from other agents (opencode / dsh / codex)

The scripts are agent-agnostic; any agent that can run bash can use them
directly:

```bash
bash task-worktree-space/scripts/task-new.sh <task> --src <source-root> --tasks-root <container>
```

Create / list / finish and `--push` behave the same for every agent (see the
natural-language examples below). The only agent-specific bit is `--agent
<name>` + `--share-memory`: only Claude Code keys auto-memory by working
directory, so it needs `--share-memory --agent claude` to create a junction;
opencode / dsh / codex keep memory in in-repo AGENTS.md or global dirs, so
`--share-memory` is a no-op.

### Natural-language prompt examples

Once installed, just invoke `/task-worktree-space` in plain language — no need to
remember script flags.

**Create a task workspace**

```
/task-worktree-space create a new workspace fix-login
/task-worktree-space start a task named add-payment
/task-worktree-space create task hotfix-auth, branch from main
/task-worktree-space create a workspace api-v2 with only the backend and frontend repos
/task-worktree-space create task share-memory-demo with shared auto-memory
/task-worktree-space create task push-demo, push to remote and track the remote branch
```

The skill asks for the task name when it is missing, and confirms the source
root, container location, and branch start point before creating anything.

"Shared auto-memory" and "push to remote" are opt-in: by default the branch is
local-only and memory is keyed per directory; they activate only when you ask
for them (mapping to `--share-memory` / `--push` respectively).

**List tasks**

```
/task-worktree-space list all task workspaces
```

**Finish / clean up**

```
/task-worktree-space finish the fix-login task
/task-worktree-space clean up the test workspace but keep the branch
/task-worktree-space finish add-payment, merge into main and delete the branch
```

Merging, branch deletion, and stray-file cleanup are each confirmed first —
documents (plans/notes not under git) are archived to
`archived-docs/<task>-<timestamp>`, build output and editor state are removed,
and you can pick which entries to keep; by default only the worktrees are
removed and both branches and stray files are kept.

See [`task-worktree-space/SKILL.md`](task-worktree-space/SKILL.md) for the full workflow.

## Adding a skill

Drop a new folder at the repo root containing a `SKILL.md` (with the required
`name` / `description` frontmatter), then add a row to the table above.

## License

[MIT](LICENSE)
