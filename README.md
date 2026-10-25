# Agent Skills

一套可复用的 [Claude Code](https://claude.com/claude-code) 技能（skill）合集。每个技能以独立的顶层目录存放，内含自包含的 `SKILL.md`（以及所需的辅助脚本），目录结构与官方 [`anthropics/skills`](https://github.com/anthropics/skills) 仓库保持一致。

> English version: [README.en.md](README.en.md)

## 技能列表

| 技能 | 说明 |
| ---- | ---- |
| [worktree-space](worktree-space/SKILL.md) | 创建并收尾跨多个仓库、按任务隔离的 git worktree 工作区：容器内按项目分层，任务目录独立于源码目录存放。 |
| [writing-docs](writing-docs/SKILL.md) | 撰写或修订文档与界面文案：代词与口语化的取舍、全称与简称的选择、对齐宿主产品自己的用语、改写既有已确认文案时的分寸，以及批量替换与验证的习惯——避免改写本身带进新缺陷。 |

## 安装

将所需技能目录复制（或软链接）到你的个人技能目录：

```bash
# Linux / macOS
cp -r worktree-space ~/.claude/skills/

# Windows（Git Bash）
cp -r worktree-space "$USERPROFILE/.claude/skills/"
```

也可以使用软链接，这样拉取本仓库后即可自动获得更新：

```bash
ln -s "$PWD/worktree-space" ~/.claude/skills/worktree-space
```

重启 Claude Code（或新开一个会话）后技能即可生效。

## 使用

每个技能的用法记录在各自的 `SKILL.md` 中。以 `worktree-space` 为例，入口是 `worktree-space/scripts/` 下的脚本：

- `task-new.sh` — 创建任务工作区
- `task-done.sh` — 清理 / 合并已完成的任务
- `task-list.sh` — 列出已有任务
- `suggest-tasks-root.sh` — 推荐任务容器存放位置

任务目录是 `<容器>/<项目>/<任务>`，项目层取源码根的目录名，分支默认 `task/<任务名>`。脚本的核心只有**创建**与**收尾**两件事，列表与位置推荐是配套的小工具；会话管理与部署验收需要宿主提供界面和会话能力，纯 skill 形态没有这些能力。

### 其他 agent 使用（opencode / dsh / codex）

脚本本身与 agent 无关，任何能运行 bash 的 agent 都能直接用：

```bash
bash worktree-space/scripts/task-new.sh <task> --src <源码根> --tasks-root <容器>
```

创建 / 列出 / 完成及 `--push` 的用法对所有 agent 一致（见下方自然语言示例）。唯一
agent 相关的是 `--agent <name>` + `--share-memory`：只有 Claude Code 把自动记忆按
工作目录隔离，需 `--share-memory --agent claude` 建 junction 共享；opencode / dsh /
codex 的记忆在仓库内 AGENTS.md 或全局目录，天然随 worktree 共享，`--share-memory`
是 no-op。

### 自然语言提示词示例

安装后，直接用自然语言调用 `/worktree-space` 即可，无需记忆脚本参数。

**创建任务工作区**

```
/worktree-space 创建新的工作区 fix-login
/worktree-space 新建一个任务，名字叫 add-payment
/worktree-space 创建任务 hotfix-auth，分支从 main 开始
/worktree-space 建一个工作区 api-v2，只包含 backend 和 frontend 两个仓库
/worktree-space 创建任务 share-memory-demo，共享自动记忆
/worktree-space 创建任务 push-demo，推送到远端并关联远端分支
```

任务名缺失时技能会追问；源码根、容器位置、分支起点也会先确认再创建。

「共享自动记忆」和「推送到远端」是可选能力：默认分支仅本地、记忆按目录隔离，只有明确说出时才启用（分别对应 `--share-memory` / `--push`）。

**查看任务**

```
/worktree-space 列出所有任务工作区
```

**收尾 / 清理**

```
/worktree-space 完成 fix-login 这个任务
/worktree-space 清理 test 工作区，但保留分支
/worktree-space 完成 add-payment，合并到 main 并删除分支
```

合并、删除分支、清理杂项文件都会先确认。选择归档（`--archive-docs`）时，任务空间里的
文档（计划/笔记等未纳入 git 的文件）会归档到 `archived-docs/<项目>/<任务名>-<时间戳>`，
构建产物与编辑器缓存（node_modules、.idea 等）直接删除，`--keep` 可保留个别文件；默认只
移除 worktree、保留分支与杂项文件。

合并只汇入源仓库**当前检出的分支**，`--target` 指定别的分支会被拒绝——脚本不改动用户
的检出状态。工作树有未提交改动、处于 detached HEAD，或源仓库不在目标分支上时，收尾会在
动手前拒绝，并点名是哪个仓库；修好后重跑即可，重跑从同一状态开始。源仓库自身有未提交
改动、合并会覆盖它时，只有 git 在合并那一刻才能判定：该仓库的合并会中止，之前的仓库可能
已经处理完。

完整流程见 [`worktree-space/SKILL.md`](worktree-space/SKILL.md)。

## 添加新技能

在仓库根目录新建一个文件夹，内含 `SKILL.md`（带有必需的 `name` / `description` 前置元数据），然后在上方表格中补充一行即可。

## 许可证

[MIT](LICENSE)
