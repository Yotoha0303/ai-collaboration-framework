# 架构成熟度评估与已知系统性问题分析（`docs/known-issues.md`）

> **本文件的角色**：按需读取的**系统性架构局限与成熟度自评报告**。
> - **不是规则源**：唯一规则源仍是 [`AGENTS.md`](../AGENTS.md)（冲突时以 `AGENTS.md` 为准，D4）。
> - **不是另立台账**：本文件分析的四类系统性问题均已映射或登记至唯一台账 [`docs/ledger.md`](ledger.md)（`GAP-001`..`GAP-026` / `DEFER-001`..`DEFER-011`）。
> - **基线口径（D1）**：文中所有文件数、行数、字节数与占比均由 `git ls-files` 口径实测得出，无一处为推断。

---

## 一、总体成熟度画像：骨架已成型，但机械化仍处早期

通过 `git ls-files` 对本仓库当前 **49 个入库文件**（不含运行态）进行实测统计，代码与文档载体的物理分布如下：

| 载体类别 | 扩展名 | 文件数 | 总行数 | 总字节数 | 占文本资产比例 | 承担职能 |
| --- | --- | --- | --- | --- | --- | --- |
| **规则、契约与文档** | `.md` | 36 | 5,871 | 478,535 B (~467.3 KB) | **92.3%** | 总控入口、唯一规则源、15 个角色契约、唯一台账及取证附录 |
| **生命周期守卫脚本** | `.ps1` | 4 | 703 | 37,436 B (~36.6 KB) | **7.2%** | 进度页 SHA 守卫、编号跨分支守卫、Antigravity 分片续载与 Stop 桥接 |
| **钩子配置文件** | `.json` | 2 | 44 | 1,155 B | **0.2%** | Claude Code (`.claude/settings.json`) 与 Antigravity (`.agents/hooks.json`) 挂载配置 |
| **启动器与仓库配置** | `.bat`/`.sh`/其他 | 6 | 79 | 3,630 B | **0.3%** | 工作目录锁定启动器、`.gitignore`、`.gitattributes`、`LICENSE`、页名指针 |
| **架构拓扑图** | `.png` | 1 | — | 620,782 B | （二进制） | `prompts/AI协同工程架构.png` |

**核心诊断一句话**：
本框架已经完成了**认知坐标系（8 系统层级 × 11 生命周期阶段）、三权分立拓扑（总控 / 执行 / 只读审计）、十环门禁矩阵与单一事实源台账**的完整骨架搭建；但 **92.3% 的资产仍是靠大模型自觉遵守的自然语言规则（Markdown），仅有 7.4% 的资产具备进程级物理拦截能力**。

---

## 二、问题域一：架构骨架更完整，但「物理咬合力」仍处于早期（`GAP-017` / `GAP-024`）

本框架的核心主张是「**纪律不能靠提醒，只能靠机制**」。但以这一标准严格自审当前实现，各层级的物理咬合力存在明显断层：

### 1. 现有物理咬合力仅覆盖「一头一尾」与「静态白名单」
目前真正不依赖模型自觉、由操作系统进程或宿主工具层强制执行的机制只有三处：
1. **回合前（`PreInvocation`）**：[`inject-agents-tail.ps1`](../.agents/hooks/inject-agents-tail.ps1)（103 行）在 Antigravity 下自动续载 `AGENTS.md` 超出 24KB 的分片。
2. **回合末（`Stop`）**：[`check-progress.ps1`](../.claude/hooks/check-progress.ps1)（283 行）强制比对进度页 HTML 的 `HEAD` 与仓库 `git rev-parse HEAD`，不一致则阻断回合结束；[`check-numbers.ps1`](../.claude/hooks/check-numbers.ps1)（237 行）扫描跨分支编号撞车（仅非阻断提示 `exit 1 + stderr`）。
3. **子代理静态权限（Claude Code 原生层）**：`.claude/agents/falsifier.md` 与 `gate-auditor.md` 通过 `tools: Read, Grep, Glob` 剥夺写文件与执行 shell 的能力。

### 2. 仍停留在「纯规则 / 提示词自觉」的核心环节（缺物理门禁）

| 规则章节 | 规范要求的硬约束 | 当前生效方式 | 暴露的「无牙」风险 | 关联台账编号 |
| --- | --- | --- | --- | --- |
| **`AGENTS.md` §2 & D2** | **十环转段强阻断**：01 设计（ADR + 带时间戳 Schema 迁移）未落盘，严禁生成 02 业务代码 | ⚠️ **纯提示词约束** | 若总控模型在长上下文产生幻觉或顺从用户的催促，可直接跳环写代码，没有任何 `PreToolUse` 或 `pre-commit` 钩子根据目录/文件状态拒绝写入 | [`GAP-017`](ledger.md) / [`GAP-024`](ledger.md) |
| **`AGENTS.md` §4.2** | **跨阶段三跳链**：每阶段结束必须依次派 `qa-validator → falsifier → gate-auditor`，缺一不得推进 | ⚠️ **半机械**（只读是机械的，派发是自觉的） | 没有任何守卫检查当前阶段是否真的产生过这三个子代理的调用记录与放行裁决 | [`GAP-017`](ledger.md) |
| **`AGENTS.md` §4.0** | **总控编排纪律**：「总控不亲自改业务代码」「单次并发角色 ≤ 3」「架构变更强制成对互审且质询 ≤ 2 轮」「子代理严禁改 `memory.md`」 | ⚠️ **纯提示词约束** | 总控拥有完整读写与命令权限；它若违反「不亲自写代码」或超并发派发，宿主层不会拦截 | [`GAP-024`](ledger.md) |
| **`AGENTS.md` §3** | **五段式交互与输出协议**：每次生成工程资产必须五段齐全（准入审查 / 可落地变更 / 正向实测 / 负向证伪 / 下游同步） | ⚠️ **纯提示词约束** | `Stop` 钩子只查进度页 SHA 与编号撞车，不解析模型本轮自然语言回复是否包含完整的五段标题 | [`GAP-024`](ledger.md) |
| **`AGENTS.md` D4** | **双语投影与文件地图同步**：`AGENTS.md` ↔ `AGENTS.en.md`、`README.md` ↔ `README.en.md` 章节结构严格对齐 | ⚠️ **人工复跑命令**（见 [`delivery-gates.md`](delivery-gates.md)） | 曾真实发生英文版漏译 `§4.2` 正文与整节 `§6.1`（`GAP-022`），在人工跑结构比对前无任何自动门禁报警 | [`GAP-017`](ledger.md) 同族 |

---

## 三、问题域二：代码载体依然具有强烈的「脚本胶水」属性（`GAP-025`）

支撑本框架机械守卫的 **703 行代码全部是 PowerShell 脚本（`.ps1`）**，外加 20 行 `.bat`/`.sh` 启动器。这种「脚本胶水」形态在框架原型期迭代极快，但在工程可靠性上暴露了四处结构性脆弱点：

### 1. 宿主平台与 Shell 环境强耦合（Windows PowerShell 5.1 绑定）
- [`.claude/settings.json`](../.claude/settings.json) 与 [`.agents/hooks.json`](../.agents/hooks.json) 的钩子命令均写死调用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...` 或 `powershell.exe`。
- 在 Linux / macOS 环境中，即便有 [`launchers/start_claude.sh`](../launchers/start_claude.sh)，PowerShell Core 的二进制名也是 `pwsh` 而非 `powershell.exe`（若未安装 `pwsh` 则直接命令找不到）。
- 脚本内部大量代码是在为 **Windows PowerShell 5.1 的历史怪癖**打补丁：
  - 原生命令写 `stderr` 配合 `$ErrorActionPreference = 'Stop'` 会被升格为终止异常并被外层 `catch` 吞没（引发 `GAP-008` 二次修复与 `GAP-013②`）；
  - 子作用域 `& { ... }` 内执行 `git` 时，`$LASTEXITCODE` 的跨作用域传递必须用 `$script:__gitExit = $LASTEXITCODE` 显式接住（见 `GAP-015`）；
  - 后台非交互进程中 `[Console]::IsInputRedirected` 恒为 `$true`，导致 `[Console]::In.ReadToEnd()` 在无 EOF 管道上永久挂死（引发 `GAP-023` 踩坑 ②）。

### 2. 基于正则的字符串抓取代替了结构化状态契约
- [`check-progress.ps1`](../.claude/hooks/check-progress.ps1) 对进度页的校验依赖正则表达式 `head\s*<b>([0-9a-fA-F]{7,40})</b>` 从 HTML 全文中抠取 SHA。
- 这种做法将「给人看的 UI 排版标签（`<div>head <b>...</b></div>`）」与「给机器验的元数据」耦合成了同一个正则。一旦前端展示样式调整（例如改成 `<span class="sha">` 或换行缩进变化），正则即失配，并触发「找不到标记时静默放行」的规则——**守卫在不报错的情况下瞬间失明**。

### 3. 缺乏统一编译/类型检查与自动化单元测试套件
- 4 个 `.ps1` 脚本目前靠 `Parser::ParseFile` 检查语法错误，靠 [`docs/guard-self-test.md`](guard-self-test.md) 中的手工沙箱脚本验证逻辑。
- 仓库内尚无一键可跑的自动化测试套件（如 Pester 或跨平台 CLI 自测命令）与 GitHub Actions CI 工作流（见 `GAP-006` / `GAP-014`），每次修改守卫都依赖维护者手工搭建临时沙箱跑 18 格攻击矩阵（见 `GAP-019` 留痕）。

---

## 四、问题域三：多运行时适配放大了「机械一致性」的验证难度（`GAP-026`）

将框架从单一的 **Claude Code** 扩展至 **Claude Code + Antigravity 双运行时**后，虽然通过「薄适配层（`GEMINI.md` + `.agents/hooks/*`）」做到了对原有文件的**零字节修改**，但双端底层机制的异构性使「证明两端行为 100% 等价」的验证成本呈乘数级上升：

| 一致性维度 | Claude Code 运行时 | Antigravity 运行时 | 放大的「机械一致性」验证痛点 |
| --- | --- | --- | --- |
| **1. 规则上下文装配通道** | `CLAUDE.md` 的 `@AGENTS.md` **单次全量内联展开**（无 24KB 单文件截断） | `user_rules` 加载前 24,000 B（在 `§4.1` 截断）+ `PreInvocation` 钩子从 23,000 B 起按 `≤24KB` 动态分片注入 `ephemeralMessage` | ① **重叠与拼接语义**：Antigravity 模型拿到的是「被截断的 `user_rules` + 含 1KB 重叠区的 `ephemeralMessage` 分片」，与 Claude Code 的连续单文档在注意力权重与位置上并不完全同构；<br>② **总预算悬崖**：Antigravity 的 `always_on` 规则受 `20,000 tokens` 总预算上限约束，未来规则扩充时可能触发跨文件级截断，且无静态报警。 |
| **2. Stop 钩子阻断与提示协议** | 原生识别 `stdout` `{"decision":"block"}`（阻断）与 `exit 1 + stderr`（非阻断提示） | 原生识别 `stdout` `{"decision":"continue","reason":"..."}`（阻断）与 `{"decision":"allow"}`（放行） | [`stop-adapter.ps1`](../.agents/hooks/stop-adapter.ps1)（80 行）作为进程外协议翻译器，必须精确解析子脚本的 `stdout` JSON 与 `stderr` 流。在适配测试中已真实踩中「把 `check-numbers.ps1` 的 `exit 1` 提示误映射为 `continue` 强阻断导致跨分支历史撞车永久死锁」（`GAP-023` 踩坑 ③）。今后原守卫新增任何退出码或输出格式，都必须同步验证转接器是否产生语义畸变。 |
| **3. 子代理挂载与只读围栏执行点** | **宿主声明式**：启动时自动扫描 `.claude/agents/*.md` 并按 YAML `tools:` 白名单物理裁剪工具（但名字不匹配会静默丢弃，`GAP-001`） | **总控命令式**：总控在运行时按需调用 `define_subagent` 读取 `.claude/agents/<role>.md` 原文，并手动传入 `enable_write_tools: false` | Claude Code 的只读围栏由**文件头静态锁定**；而 Antigravity 的只读围栏依赖**总控每次调用 `define_subagent` 时不漏写 `enable_write_tools: false`**——防线从「静态配置」退回到了「总控调用时的参数正确性」，且目前无 `PreToolUse` 钩子校验 `define_subagent` 的入参。 |
| **4. 回归测试矩阵膨胀** | 每次守卫改动跑 1 套沙箱矩阵 | 每次守卫或规则改动需跑「原守卫 + 转接器 + 分片器」2 套组合矩阵 | 缺乏跨运行时契约对拍工具（Contract Test Runner），全靠人工在双端分别实测。 |

---

## 五、问题域四：已登记的深水区缺口依然待解（`GAP-002/005/012/013/017/019` · `DEFER-001..011`）

在唯一台账 [`docs/ledger.md`](ledger.md) 中，除了已解除的常规工程缺陷外，仍有一批触及**「观测等价性」「自指矛盾」与「可信基边界」**的深水区缺口处于 `未解除`、`已缓解（残余）` 或 `待人工裁定` 状态：

### 1. 观测等价性与防伪造死角（技术深水区）
- **[`GAP-005`](ledger.md)（只读角色「代跑是否真的发生」无机械判据 · `未解除`）**：
  - 为保证机械只读，`falsifier` 与 `gate-auditor` 被剥夺了 shell 权限，改由「只读角色出攻击命令清单 → 总控代跑 → 回灌真实 stdout → 只读角色判分」。
  - **死角**：若总控偷懒未跑命令（或伪造 stdout），只读角色拿不到独立进程级签名；而当回灌缺失时，只读角色输出 `无法判定`，在外观上与「环境确实无 shell」完全一致。目前的「最小锚」（要求总控在 `record.md` 留痕）仍是事后审计且依赖总控自写。
- **[`GAP-002` 残余](ledger.md) & [`GAP-012`](ledger.md)（「尚未初始化」与「守卫失明」观测等价 · `已缓解/未解除`）**：
  - 当 `.claude/progress-page.txt` 指向一个不存在的页名，或仓库处于 `git init` 后零提交的 unborn 状态时，守卫必须静默 `exit 0`（否则新项目每一轮都会误报阻断）。
  - **死角**：这种合法的「静默 `exit 0`」与「守卫脚本逻辑坏死导致的静默 `exit 0`」在单次观测上**逐字节相同**，只能靠周期性在隔离沙箱中同跑「缺页正控 + 错 SHA 负控」双用例来反推守卫存活。
- **[`GAP-013①`](ledger.md) & [`GAP-019` 残余](ledger.md)（底层环境与 `git` 二进制可信边界 · `未解除/已缓解`）**：
  - 外部若设置 `GIT_DIR` 环境变量，会劫持守卫内未加 `--git-dir` 的 `git rev-parse` 调用；
  - 若 `PATH` 上被注入一个「聪明 shim」——专门对 `git --version` 返回 `exit 0`、对全零 commit 金丝雀返回 `exit 1`，而对业务查询（`rev-parse HEAD` / `ls-tree`）恒返回 `exit 0` 与假数据——则在「以 git 退出码为唯一判据」的规则体系内**逻辑上不可消**（既要信退出码、又要防退出码被精准伪造，二者同源互斥，见 `DEFER-010`）。

### 2. 架构演进与人工价值裁定积压（`DEFER-001..011`）
- **功能性主动延期（`[目前不做]`）**：
  - [`DEFER-001`](ledger.md)：命令行一键将框架引入业务项目并自动嵌套工作空间；
  - [`DEFER-004`](ledger.md)：常驻核心与按需记忆库（角色契约库 / 提示词库）的动态分层与按需生成架构；
  - [`DEFER-006`](ledger.md)：根据业务项目的领域特征自动识别并生成缺失的领域 Agent 角色。
- **待人工价值裁定项（[`DEFER-007`..`DEFER-011`](ledger.md)）**：
  - 模板仓是否要把 `GAP-017`（`§4.2` 机械守卫）建出来当示范品（`DEFER-007`）、`AGENTS.md`/`AGENTS.en.md` 体量是否继续拆分（`DEFER-008`）、台账历史行乱序是否移动（`DEFER-009`）、`GAP-019` 同源互斥残余追到哪一步算够（`DEFER-010`）、跨平台不可达用例（如 Windows 下含双引号路径）是否换平台补跑（`DEFER-011`）。

---

## 六、收敛路线图（怎么把「早期咬合 + 脚本胶水」推向下一阶段）

针对上述四大已知问题域，框架后续演进按以下优先级收敛（任何一项动手前均须遵循 `AGENTS.md` §0.2 双锚与 D3 负向用例先行）：

1. **从「回合末 Stop 守卫」前移到「动作前 `PreToolUse` / Git `pre-commit` 守卫」（解 `GAP-017` / `GAP-024`）**：
   - 增加 `PreToolUse` 钩子：在 Antigravity 下拦截 `define_subagent` 调用，强制核验当目标角色为 `falsifier` / `gate-auditor` 时必须显式带有 `enable_write_tools: false`（补齐双运行时只读围栏缺口 `GAP-026`）；
   - 增加阶段准入守卫（`check-stage.ps1`）：在修改业务代码目录前，机械检查 `docs/adr/` 与 `docs/changes/` 是否存在对应阶段的准入资产。
2. **用结构化状态元数据替代 HTML 正则抓取，并收敛跨平台宿主依赖（解 `GAP-025`）**：
   - 在进度页 HTML 中引入机器可读的固定注释头或 `<script type="application/json" id="progress-meta">`，消除排版改动导致正则失配的静默失明风险；
   - 将 `.claude/hooks/` 与 `.agents/hooks/` 的手工沙箱验证脚本封装为可一键执行的跨平台自测入口（支持 `pwsh` / `powershell` 自动探测），纳入 CI 自动化回归。
3. **建立双运行时契约对拍脚本（解 `GAP-026`）**：
   - 编写自动化对拍检查：静态核验 `CLAUDE.md` 与 `GEMINI.md` 的导入列表一致性、中英文 Markdown 标题树 1:1 对齐（固化 `GAP-022` 核对命令）、以及 `stop-adapter.ps1` 对所有子守卫返回码的映射完备性。
