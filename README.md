# Agent Skills

一套可复用的 [Claude Code](https://claude.com/claude-code) 技能（skill）合集。每个技能以独立的顶层目录存放，内含自包含的 `SKILL.md`（以及所需的辅助脚本），目录结构与官方 [`anthropics/skills`](https://github.com/anthropics/skills) 仓库保持一致。

> English version: [README.en.md](README.en.md)

## 技能列表

| 技能 | 说明 |
| ---- | ---- |
| [task-workspace](task-workspace/SKILL.md) | 创建并管理跨多个仓库、按任务隔离的 git worktree 工作区，任务容器独立于源码目录存放。 |

## 安装

将所需技能目录复制（或软链接）到你的个人技能目录：

```bash
# Linux / macOS
cp -r task-workspace ~/.claude/skills/

# Windows（Git Bash）
cp -r task-workspace "$USERPROFILE/.claude/skills/"
```

也可以使用软链接，这样拉取本仓库后即可自动获得更新：

```bash
ln -s "$PWD/task-workspace" ~/.claude/skills/task-workspace
```

重启 Claude Code（或新开一个会话）后技能即可生效。

## 使用

每个技能的用法记录在各自的 `SKILL.md` 中。以 `task-workspace` 为例，入口是 `task-workspace/scripts/` 下的脚本：

- `task-new.sh` — 创建任务工作区
- `task-done.sh` — 清理 / 合并已完成的任务
- `task-list.sh` — 列出已有任务
- `suggest-tasks-root.sh` — 推荐任务容器存放位置

完整流程见 [`task-workspace/SKILL.md`](task-workspace/SKILL.md)。

## 添加新技能

在仓库根目录新建一个文件夹，内含 `SKILL.md`（带有必需的 `name` / `description` 前置元数据），然后在上方表格中补充一行即可。

## 许可证

[MIT](LICENSE)
