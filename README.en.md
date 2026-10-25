# Agent Skills

A collection of reusable [Claude Code](https://claude.com/claude-code) skills. Each
skill lives in its own top-level directory as a self-contained `SKILL.md` (plus any
helper scripts it needs), following the same layout as the official
[`anthropics/skills`](https://github.com/anthropics/skills) repository.

> 中文版：[README.md](README.md)

## Skills

| Skill | Description |
| ----- | ----------- |
| [worktree-space](worktree-space/SKILL.md) | Create and finish isolated per-task git worktree workspaces that span multiple repositories under a source root, with each source root filed under its own project layer. |
| [writing-docs](writing-docs/SKILL.md) | Write or revise documentation and UI copy (the skill itself is written in Chinese): pronoun and colloquialism judgement, full term vs abbreviation, matching a host product's own vocabulary, scope discipline when rewriting approved copy, and the batch-edit and verification habits that keep a rewrite from adding defects. |

## Install

Copy (or symlink) the skill folder you want into your personal skills directory:

```bash
# Linux / macOS
cp -r worktree-space ~/.claude/skills/

# Windows (Git Bash)
cp -r worktree-space "$USERPROFILE/.claude/skills/"
```

Or symlink it so you always get updates when you pull this repo:

```bash
ln -s "$PWD/worktree-space" ~/.claude/skills/worktree-space
```

Restart Claude Code (or start a new session) and the skill will be available.

## Usage

Each skill documents its own usage inside its `SKILL.md`. For `worktree-space`, the
entry points are the scripts under `worktree-space/scripts/`:

- `task-new.sh` — create a task workspace
- `task-done.sh` — clean up / merge a finished task
- `task-list.sh` — list existing tasks
- `suggest-tasks-root.sh` — recommend where to put the task container

A task directory is `<container>/<project>/<task>`, with the project layer taken
from the source root's own directory name and the branch defaulting to
`task/<task>`. Create and finish are the two core jobs; list and suggest-root
are helpers. Session control and deploy acceptance need a host with a UI and
sessions; a plain skill has neither.

### Using from other agents (opencode / dsh / codex)

The scripts are agent-agnostic; any agent that can run bash can use them
directly:

```bash
bash worktree-space/scripts/task-new.sh <task> --src <source-root> --tasks-root <container>
```

Create / list / finish and `--push` behave the same for every agent (see the
natural-language examples below). The only agent-specific bit is `--agent
<name>` + `--share-memory`: only Claude Code keys auto-memory by working
directory, so it needs `--share-memory --agent claude` to create a junction;
opencode / dsh / codex keep memory in in-repo AGENTS.md or global dirs, so
`--share-memory` is a no-op.

### Natural-language prompt examples

Once installed, just invoke `/worktree-space` in plain language — no need to
remember script flags.

**Create a task workspace**

```
/worktree-space create a new workspace fix-login
/worktree-space start a task named add-payment
/worktree-space create task hotfix-auth, branch from main
/worktree-space create a workspace api-v2 with only the backend and frontend repos
/worktree-space create task share-memory-demo with shared auto-memory
/worktree-space create task push-demo, push to remote and track the remote branch
```

The skill asks for the task name when it is missing, and confirms the source
root, container location, and branch start point before creating anything.

"Shared auto-memory" and "push to remote" are opt-in: by default the branch is
local-only and memory is keyed per directory; they activate only when you ask
for them (mapping to `--share-memory` / `--push` respectively).

**List tasks**

```
/worktree-space list all task workspaces
```

**Finish / clean up**

```
/worktree-space finish the fix-login task
/worktree-space clean up the test workspace but keep the branch
/worktree-space finish add-payment, merge into main and delete the branch
```

Merging, branch deletion, and stray-file cleanup are each confirmed first. With
`--archive-docs`, documents (plans/notes not under git) are archived to
`archived-docs/<project>/<task>-<timestamp>`, build output and editor state are
removed, and `--keep` retains the entries you name; by default only the
worktrees are removed and both branches and stray files are kept.

A merge only lands on the branch the source repository has **checked out**; a
`--target` naming another branch is refused, because the script does not move
somebody else's checkout. A worktree with uncommitted work, a detached HEAD, or
a source repository on another branch stops the finish before anything changes,
naming the repository; fix it and run again. A source checkout whose own changes
a merge would overwrite can only be detected when git attempts that merge: that
repository's merge is aborted, while repositories processed before it may
already be finished.

See [`worktree-space/SKILL.md`](worktree-space/SKILL.md) for the full workflow.

## Adding a skill

Drop a new folder at the repo root containing a `SKILL.md` (with the required
`name` / `description` frontmatter), then add a row to the table above.

## License

[MIT](LICENSE)
