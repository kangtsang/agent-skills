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

脚本本身与 agent 无关，可直接被 Claude Code / opencode / dsh / codex 复用；
`--share-memory` 通过 `adapters/<agent>/memory-hook.sh` 适配各 agent（内置
`claude` / `opencode` / `dsh` / `codex`）。

### 自然语言提示词示例

安装后，直接用自然语言调用 `/task-workspace` 即可，无需记忆脚本参数。

**创建任务工作区**

```
/task-workspace 创建新的工作区 fix-login
/task-workspace 新建一个任务，名字叫 add-payment
/task-workspace 创建任务 hotfix-auth，分支从 main 开始
/task-workspace 建一个工作区 api-v2，只包含 backend 和 frontend 两个仓库
/task-workspace 创建任务 share-memory-demo，共享自动记忆
/task-workspace 创建任务 push-demo，推送到远端并关联远端分支
```

任务名缺失时技能会追问；源码根、容器位置、分支起点也会先确认再创建。

「共享自动记忆」和「推送到远端」是可选能力：默认分支仅本地、记忆按目录隔离，只有明确说出时才启用（分别对应 `--share-memory` / `--push`）。

**查看任务**

```
/task-workspace 列出所有任务工作区
```

**收尾 / 清理**

```
/task-workspace 完成 fix-login 这个任务
/task-workspace 清理 test 工作区，但保留分支
/task-workspace 完成 add-payment，合并到 main 并删除分支
```

合并与删除分支会先确认；默认只移除 worktree、保留分支。

完整流程见 [`task-workspace/SKILL.md`](task-workspace/SKILL.md)。

## 添加新技能

在仓库根目录新建一个文件夹，内含 `SKILL.md`（带有必需的 `name` / `description` 前置元数据），然后在上方表格中补充一行即可。

## 许可证

[MIT](LICENSE)
