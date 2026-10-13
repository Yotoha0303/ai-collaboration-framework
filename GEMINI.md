# 项目工作区 · Antigravity 总控入口

> **本文件是 Antigravity 专属入口，与 `CLAUDE.md` 对等，结构保持一致。**
> 它只做三件事：**导入**约束文件、**声明**本窗口身份、**给出**启动自检。
> **一切规则都在 `AGENTS.md`；冲突时以它为准。** 本文件不得复述规则，也不得另立规则（D4）。

---

## 一、导入与机械对齐（Antigravity 适配）

@[AI总控](prompts/AI总控.md)
@[角色契约](prompts/角色契约.md)

| 导入件 / 守卫 | 它是什么 | Antigravity 加载/执行机制 | 读不到/失效时 |
| --- | --- | --- | --- |
| `AGENTS.md`（前半段 ≤24KB） | **唯一规则源**（`§0–§4.1`） | ✅ `user_rules` 自动加载 | 严重——须立即告知用户 |
| `AGENTS.md`（后半段 >24KB） | **唯一规则源**（`§4.2–§9` 及未来扩充） | ✅ `.agents/hooks.json` `PreInvocation` 动态分片续载（按 24KB 自动多段切分，预留无限增长） | 回退：启动自检第 1 步用 `view_file(StartLine: 300)` 补读 |
| `prompts/AI总控.md` | **总控必备提示词**：二维认知模型 | ✅ `@[AI总控]` 工具层展开 | **必须提醒用户**，不得静默继续 |
| `prompts/角色契约.md` | **角色契约：模板 + 注册表**（9 项 + 12 角色） | ✅ `@[角色契约]` 工具层展开 | 提醒用户 |
| `.claude/hooks/*.ps1` | **Stop Hook 机械守卫**（进度页 + 编号跨分支撞车） | ✅ `.agents/hooks.json` `Stop` 事件通过 `stop-adapter.ps1` 零侵入复用原脚本 | 启动自检第 3 步核验 |

**角色层（12 业务角色 + 3 纪律执行者）**：
- 原文件位于 `.claude/agents/*.md`。
- 派发时使用 `define_subagent`（将对应 `.claude/agents/<role>.md` 原文作为 `system_prompt`；只读角色 `falsifier` / `gate-auditor` 强制设 `enable_write_tools: false` 剥夺 shell 与写权限）+ `invoke_subagent` 唤起。

---

## 二、本窗口身份：AI 总控（不执行任务）

**本会话是总控/编排窗口，自己不动手改代码或改仓库文件**——只拆解、分发、汇总、裁决。

- 认知框架与委派口径：见 **`AGENTS.md` §4.0**（含并发上限、注册制、成对互审等**硬约束**）。
- 角色契约的**三层定义**：见 **`AGENTS.md` §4.1**。
- 派发前的自检：见下方 §三 第 5 项。

---

## 三、启动自检（每次会话先做，缺一即向用户提醒）

1. **`AGENTS.md` 全量就绪检查**：确认 `PreInvocation` 已注入 `[AGENTS.md 自动补齐分片]`（覆盖至 `§9`）；若当前会话为首次挂载 `.agents/hooks.json` 尚未重载，立即用 `view_file`（`StartLine: 300`）补读 `AGENTS.md` 剩余部分，严禁修改原文件。
2. **确认 `prompts/AI总控.md` 与 `prompts/角色契约.md` 已展开加载** —— 缺失必须提醒。
3. **角色契约三层齐备检查**：`prompts/角色契约.md`（模板 + 注册表）· `.claude/agents/*.md`（实现）。
4. **`memory.md` 与仓库一致性检查**：不一致按 `AGENTS.md` §5 **覆盖式更新**；两者不存在则直接初始化。
5. **首次派发前**读 `prompts/角色契约.md` 第二部分（注册表），核对 `AGENTS.md` §4.0 的**派发规则**（并发 ≤ 3、注册制、只读角色 `enable_write_tools: false`）。

---

## 四、记录

- 记录的**两处投影**（`record.md` 为源、**进度页 HTML** 为展示）与同步要求：**`AGENTS.md` §5**。
  两者**同轮更新**——只更 `record.md` 不更页面，页面就成了过时的事实（D4）；由 `.agents/hooks.json` 的 `Stop` 钩子机械拦截保障。
