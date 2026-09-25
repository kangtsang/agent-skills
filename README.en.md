# Agent Skills

A collection of reusable [Claude Code](https://claude.com/claude-code) skills. Each
skill lives in its own top-level directory as a self-contained `SKILL.md` (plus any
helper scripts it needs), following the same layout as the official
[`anthropics/skills`](https://github.com/anthropics/skills) repository.

> 中文版：[README.md](README.md)

## Skills

| Skill | Description |
| ----- | ----------- |
| [task-workspace](task-workspace/SKILL.md) | Create and manage isolated per-task git worktree workspaces that span multiple repositories under a source root. |

## Install

Copy (or symlink) the skill folder you want into your personal skills directory:

```bash
# Linux / macOS
cp -r task-workspace ~/.claude/skills/

# Windows (Git Bash)
cp -r task-workspace "$USERPROFILE/.claude/skills/"
```

Or symlink it so you always get updates when you pull this repo:

```bash
ln -s "$PWD/task-workspace" ~/.claude/skills/task-workspace
```

Restart Claude Code (or start a new session) and the skill will be available.

## Usage

Each skill documents its own usage inside its `SKILL.md`. For `task-workspace`, the
entry points are the scripts under `task-workspace/scripts/`:

- `task-new.sh` — create a task workspace
- `task-done.sh` — clean up / merge a finished task
- `task-list.sh` — list existing tasks
- `suggest-tasks-root.sh` — recommend where to put the task container

### Natural-language prompt examples

Once installed, just invoke `/task-workspace` in plain language — no need to
remember script flags.

**Create a task workspace**

```
/task-workspace create a new workspace fix-login
/task-workspace start a task named add-payment
/task-workspace create task hotfix-auth, branch from main
/task-workspace create a workspace api-v2 with only the backend and frontend repos
/task-workspace create task share-memory-demo with shared auto-memory
/task-workspace create task push-demo, push to remote and track the remote branch
```

The skill asks for the task name when it is missing, and confirms the source
root, container location, and branch start point before creating anything.

"Shared auto-memory" and "push to remote" are opt-in: by default the branch is
local-only and memory is keyed per directory; they activate only when you ask
for them (mapping to `--share-memory` / `--push` respectively).

**List tasks**

```
/task-workspace list all task workspaces
```

**Finish / clean up**

```
/task-workspace finish the fix-login task
/task-workspace clean up the test workspace but keep the branch
/task-workspace finish add-payment, merge into main and delete the branch
```

Merging and branch deletion are confirmed first; by default only the worktrees
are removed and branches are kept.

See [`task-workspace/SKILL.md`](task-workspace/SKILL.md) for the full workflow.

## Adding a skill

Drop a new folder at the repo root containing a `SKILL.md` (with the required
`name` / `description` frontmatter), then add a row to the table above.

## License

[MIT](LICENSE)
