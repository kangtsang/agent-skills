# Agent Skills

一套可复用的 [Claude Code](https://claude.com/claude-code) 技能（skill）合集。每个技能以独立的顶层目录存放，内含自包含的 `SKILL.md`（以及所需的辅助脚本），目录结构与官方 [`anthropics/skills`](https://github.com/anthropics/skills) 仓库保持一致。

> English version: [README.en.md](README.en.md)

## 技能列表

| 技能 | 说明 |
| ---- | ---- |
| [task-worktree-space](task-worktree-space/SKILL.md) | 创建并管理跨多个仓库、按任务隔离的 git worktree 工作区，任务容器独立于源码目录存放。 |

## 安装

将所需技能目录复制（或软链接）到你的个人技能目录：

```bash
# Linux / macOS
cp -r task-worktree-space ~/.claude/skills/

# Windows（Git Bash）
cp -r task-worktree-space "$USERPROFILE/.claude/skills/"
```

也可以使用软链接，这样拉取本仓库后即可自动获得更新：

```bash
ln -s "$PWD/task-worktree-space" ~/.claude/skills/task-worktree-space
```

重启 Claude Code（或新开一个会话）后技能即可生效。

## 使用

每个技能的用法记录在各自的 `SKILL.md` 中。以 `task-worktree-space` 为例，入口是 `task-worktree-space/scripts/` 下的脚本：

- `task-new.sh` — 创建任务工作区
- `task-done.sh` — 清理 / 合并已完成的任务
- `task-list.sh` — 列出已有任务
- `suggest-tasks-root.sh` — 推荐任务容器存放位置

### 其他 agent 使用（opencode / dsh / codex）

脚本本身与 agent 无关，任何能运行 bash 的 agent 都能直接用：

```bash
bash task-worktree-space/scripts/task-new.sh <task> --src <源码根> --tasks-root <容器>
```

创建 / 列出 / 完成及 `--push` 的用法对所有 agent 一致（见下方自然语言示例）。唯一
agent 相关的是 `--agent <name>` + `--share-memory`：只有 Claude Code 把自动记忆按
工作目录隔离，需 `--share-memory --agent claude` 建 junction 共享；opencode / dsh /
codex 的记忆在仓库内 AGENTS.md 或全局目录，天然随 worktree 共享，`--share-memory`
是 no-op。

### 自然语言提示词示例

安装后，直接用自然语言调用 `/task-worktree-space` 即可，无需记忆脚本参数。

**创建任务工作区**

```
/task-worktree-space 创建新的工作区 fix-login
/task-worktree-space 新建一个任务，名字叫 add-payment
/task-worktree-space 创建任务 hotfix-auth，分支从 main 开始
/task-worktree-space 建一个工作区 api-v2，只包含 backend 和 frontend 两个仓库
/task-worktree-space 创建任务 share-memory-demo，共享自动记忆
/task-worktree-space 创建任务 push-demo，推送到远端并关联远端分支
```

任务名缺失时技能会追问；源码根、容器位置、分支起点也会先确认再创建。

「共享自动记忆」和「推送到远端」是可选能力：默认分支仅本地、记忆按目录隔离，只有明确说出时才启用（分别对应 `--share-memory` / `--push`）。

**查看任务**

```
/task-worktree-space 列出所有任务工作区
```

**收尾 / 清理**

```
/task-worktree-space 完成 fix-login 这个任务
/task-worktree-space 清理 test 工作区，但保留分支
/task-worktree-space 完成 add-payment，合并到 main 并删除分支
```

合并、删除分支、清理杂项文件都会先确认。任务空间里的文档（计划/笔记等未纳入
git 的文件）会归档到 `archived-docs/<任务名>-<时间戳>`，构建产物与编辑器缓存
（node_modules、.idea 等）直接删除，也可勾选保留个别文件；默认只移除 worktree、
保留分支与杂项文件。

完整流程见 [`task-worktree-space/SKILL.md`](task-worktree-space/SKILL.md)。

## 添加新技能

在仓库根目录新建一个文件夹，内含 `SKILL.md`（带有必需的 `name` / `description` 前置元数据），然后在上方表格中补充一行即可。

## 许可证

[MIT](LICENSE)
