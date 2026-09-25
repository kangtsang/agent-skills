# task-workspace

Isolate per-task git worktree workspaces outside the source tree. Use when the
user wants to start or finish a task/feature in an isolated worktree. The
scripts are agent-agnostic bash under `<skill-root>/scripts/`.

## Create a task

```bash
bash <skill-root>/scripts/task-new.sh <task-name> --src <source-root> --tasks-root <tasks-root>
```

Creates `<tasks-root>/<task>/` with a worktree of each repo, all on branch
`feat/<task>`.

## List tasks

```bash
bash <skill-root>/scripts/task-list.sh --tasks-root <tasks-root>
```

## Finish a task

```bash
bash <skill-root>/scripts/task-done.sh <task-name> --tasks-root <tasks-root>
```

Default: removes the worktrees, keeps the branches. Add `--merge --target main
--delete-branch` only when the user explicitly asks to merge.

## Opt-in flags

- `--push` — push the new branch to origin and set upstream (only when the
  user explicitly asks; default is local-only).
- `--share-memory` — no-op for codex: instructions are in `AGENTS.md`
  (global `~/.codex/AGENTS.md` + per-repo) and memories in the global
  `~/.codex/memories/`; neither is keyed by directory, so memory is already
  shared. Omit it.
