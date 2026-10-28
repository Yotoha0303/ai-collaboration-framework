# 004 · 写方角色 `tools` 跨平台适配（PowerShell → Bash）

- **日期**：2026-10-28（UTC）
- **分支**：`feat/aicf-guard`（自 `main` `074340e` 切出）
- **关联**：路线图 `P1.2` · 台账 `GAP-025`②（Go CLI `aicf-guard` 跨平台改造的**独立第一步**）
- **性质**：框架基础设施层改动——`.claude/agents/*.md`（角色实现层 frontmatter + 正文 shell 名表述）+
  `.claude/agents/README.md`。**不改** `.claude/hooks/*.ps1`（留待 Go CLI 阶段）、**不改** `memory.md`、
  **不改** 只读角色围栏表述、**不改** 历史/技术事实。
- **记录方式**：**先写后填**。本条先立；下方的实测结果于改动落地后回填。

> ⚠️ **编号待总控跨分支并集确认**：本子代理**无 shell**（`tools` 里 `PowerShell` 在 Linux 被丢弃，
> 实际仅 `Read/Write/Edit/Grep/Glob`），**跑不了 `git ls-tree`**。Glob 仅见当前分支 `docs/changes/001`；
> `002`/`003` 据总控在 `feat/procedure-memory` 分支。`004` 是否被占须总控按下文「四 · 待总控代跑命令」
> 逐 ref `ls-tree` 并集确认后再提交。**若 `004` 已被占，总控 rename 本文件后提交。**

---

## 一、为什么要改

用户从 Windows 迁到 Linux。本机实测（总控跑）：`which pwsh` / `which powershell` 都未找到（未安装）；
shell 是 `bash 5.3`；Go 工具链 `go1.27.3` 已装。

**问题**：13 个写方角色 frontmatter `tools: Read, Write, Edit, Grep, Glob, PowerShell`——
在 Linux 上 `PowerShell` 被 Claude Code **静默丢弃**（见 `.claude/agents/README.md:28-35`），
写方角色失去 shell，**跑不了 `go test` / `tsc` / `git`**。这与「能力缺失」**外观完全相同、不报错**
（`AGENTS.md` §8「静默地错」家族）。

**`AGENTS.md` §4.1 与 `.claude/agents/README.md:31` 本就明写**「换机（macOS/Linux 为 `Bash`）时按实测改」
——**但未改**。本步即补上：把写方 `tools` 的 shell 名按**本机实测**改为 `Bash`，
并把正文中「本机（Windows）shell 名为 `PowerShell`」一类**本机断言**泛化为跨平台表述
（保留「换机须按实测改」的告诫——这条仍正确，是 `AGENTS.md` §4.1 的口径）。

**为什么是「独立第一步」**：这是 Go CLI `aicf-guard`（`GAP-025`②）跨平台改造中**纯文档/声明层**的一步——
不涉及 `.ps1` 守卫脚本的重写（那是后续 Go CLI 阶段），只让写方角色在 Linux 上**先恢复 shell 能力**，
使后续 Go CLI 开发（`backend-dev` 跑 `go test`、`frontend-dev` 跑 `tsc`）成为可能。

## 二、改了什么（逐文件）

### A · 13 个写方角色 frontmatter `tools:` 行（机械改 `PowerShell` → `Bash`）

每个文件都是 line 4，`tools: Read, Write, Edit, Grep, Glob, PowerShell` → `tools: Read, Write, Edit, Grep, Glob, Bash`：

| 文件 | 行 |
| --- | --- |
| `.claude/agents/backend-dev.md` | 4 |
| `.claude/agents/biz-strategist.md` | 4 |
| `.claude/agents/contract-dev.md` | 4 |
| `.claude/agents/data-engineer.md` | 4 |
| `.claude/agents/finops-controller.md` | 4 |
| `.claude/agents/frontend-dev.md` | 4 |
| `.claude/agents/pm-spec-driver.md` | 4 |
| `.claude/agents/qa-validator.md` | 4 |
| `.claude/agents/rca-investigator.md` | 4 |
| `.claude/agents/sec-auditor.md` | 4 |
| `.claude/agents/sre-operator.md` | 4 |
| `.claude/agents/ssot-scribe.md` | 4 |
| `.claude/agents/system-architect.md` | 4 |

### B · 正文「本机（Windows）shell 名为 `PowerShell`」断言（改为跨平台泛化表述）

| 文件 | 行 | 改动要点 |
| --- | --- | --- |
| `frontend-dev.md` | 9-10（注释块） | 「本机（Windows）shell 名为 `PowerShell`」→ 跨平台映射（Windows=`PowerShell`/Linux·macOS=`Bash`），注明本机现 Linux 实测为 `Bash`；**保留**「换机须按实测改 `tools:`」告诫 |
| `contract-dev.md` | 9-10（注释块） | 同上 |
| `ssot-scribe.md` | 9-11（注释块） | 同上 |
| `ssot-scribe.md` | 17-18 | 「本机 shell 名为 `PowerShell`……`Bash` 在本机解析不了」→ 跨平台映射 + 注明本机现 Linux 实测为 `Bash`；保留「名字写错会被静默丢弃、不等于没有 shell」 |
| `ssot-scribe.md` | 46-47 | 「有 shell（本机 `PowerShell`）时用……`Test-Path`」→ 跨平台映射 + 命令示例补 `test -f`（Windows PowerShell 用 `Test-Path`），避免「本机现 Linux」却只给 PowerShell 命令的新漂移 |

### C · `.claude/agents/README.md:29`（本机断言泛化）

「本机（Windows）实测挂载名是 `PowerShell`，不是 `Bash`」→ 跨平台映射（Windows=`PowerShell`/Linux·macOS=`Bash`），
注明本机现 Linux 实测为 `Bash`；**保留**「框架建立时在 Windows 上曾据 `Bash` 被丢弃误诊为没有 shell」这一
**历史事实**（是历史快照，不是当前本机断言）；`:31`「换机时按实测改」告诫已是跨平台口径，保留。

### D · `.claude/agents/README.md:56`（历史快照，**不改写**，其后加注）

line 56「回报工具清单 = `Read, Write, Edit, Grep, Glob, PowerShell`，并真跑了命令」是 `2026-10-14` 写方探针
实测留痕——**历史快照不改写**（`AGENTS.md` §5）。**在其后**（line 61「换机后须重测」之后）加一行
**带日期的补注**：本机已迁 Linux（`bash 5.3`，无 `pwsh`），写方 `tools` 已由 `PowerShell` 改为 `Bash`，
只读角色不变。**不改写原行。**

### E · 明确不改（边界）

| 项 | 为什么不改 |
| --- | --- |
| 只读角色 `falsifier.md:4` / `gate-auditor.md:4` `tools: Read, Grep, Glob` | 本就无 shell，跨平台通用 |
| `falsifier.md:10,22` / `gate-auditor.md:10,22`「刻意不列 `Bash`，也刻意不列 `PowerShell`」 | 只读围栏**设计**，跨平台通用——改了反而破坏表述 |
| `falsifier.md:25`「你永远没有 shell（常态，不是条件）」 / `:11`「理由不是本机没有 shell」 / `:49`「CRLF 本机读数」 | 设计陈述 / 技术事实，非本机断言 |
| `README.md:28`「必须与本机实际挂载名一致」 | 跨平台通用真理，无需改 |
| `.claude/hooks/*.ps1` | 留待 Go CLI 阶段（`GAP-025`②），本轮不动；**改它须过 `falsifier`**（硬边界） |
| `memory.md` | 由总控统一沉淀（注册表硬约束） |

## 三、怎么验证

### 3.1 正向实测（本子代理能跑的：Grep/Read 文本级核验）

| 判据 | 命令（Grep） | 预期 |
| --- | --- | --- |
| 13 个写方 frontmatter 全部改为 `Bash` | `Grep "^tools:"` in `.claude/agents/` | 13 行含 `Bash`；2 行只读仍 `Read, Grep, Glob` |
| 写方 frontmatter 不再含 `PowerShell` | `Grep "tools:.*PowerShell"` | **零命中** |
| scope B 正文断言已泛化（不再有「本机（Windows）shell 名为 `PowerShell`」原句） | `Grep "本机（Windows）shell 名为"` | **零命中** |
| 只读围栏表述保留 | `Grep "刻意不列.*Bash.*PowerShell"` | 命中 `falsifier.md` / `gate-auditor.md` 各 2 处 |
| README `:29` 已泛化、`:56` 原行保留 | `Read` README.md:28-35 / 55-62 | `:56` 原文不动；`:29` 跨平台；补注存在 |

### 3.2 负向 / 待验证（本子代理**跑不了**的，如实标注）

- **`tools:` 是声明，挂载才是事实**（`README.md:28-35`）——Grep 只能证**文本改对**，
  **证不了 Claude Code 在 Linux 上真的把 `Bash` 挂载给写方子代理**。这是本改动的**核心风险**：
  若 `Bash` 在本机也被丢弃（例如挂载名实为别的），写方仍无 shell，且**不报错**。
  **判据（须总控代跑）**：派一个写方探针（如 `biz-strategist`），令其**自报工具清单的确切名字**并跑
  最小命令回灌 stdout——`pwd; echo probe-ok; echo "exit=$?"`。**通过**：stdout 含绝对路径 + `probe-ok` +
  `exit=0`。**只读探针**（`falsifier`）应回「没有 shell 工具，无法执行」。
  ⇒ **本项标 `[未能验证]`，列命令交总控代跑**（`AGENTS.md` §4.1 协同纪律：只读角色执行交总控代跑；
  此处写方角色虽非只读，但**本子代理自身无 shell**，同理交总控代跑）。
- **跨分支编号并集**：`004` 是否被占须 `git ls-tree` 逐 ref 确认（见「四」）。`[未能验证]`。
- **`self-test.ps1` 的 `F1`/`F2`**（写方必须有 shell · 只读不得带 shell）：本改动**应**让其继续绿
  （写方仍有 shell=`Bash`，只读仍无 shell），但 `F1`/`F2` 的判据若**硬编码** `PowerShell` 而非「有任一 shell」，
  改后会变红。**本轮不动 `.ps1`**——若 `F1`/`F2` 因此红，是**判据需同步**（属下游同步，见「四」），
  **不是本改动错了**。`[未能验证]`，列命令交总控代跑 `self-test.ps1` 看读数。

### 3.3 回填（改动落地后，Grep 复测结果）

> 待回填——见文末「五、回填」。

## 四、下游同步与待总控代跑命令

### 4.1 本轮触发的文档联动（列出，**本轮不一定全改**，由总控裁定分批）

| 联动项 | 说明 | 本轮是否改 |
| --- | --- | --- |
| `AGENTS.md` §4.1「协同纪律」实测读数 | 原文记 `2026-10-14` 写方探针回报 `…PowerShell`；本机迁 Linux 后该读数已变（应为 `…Bash`）。属**历史快照**——按 §5「历史快照不改写」，**宜在其后加注**而非改写（同 README `:56` 处理）。 | 否（交总控裁定，避免本轮扩面） |
| `AGENTS.md` §4.1「换机（macOS/Linux 为 `Bash`）时按实测改」 | 该句已是正确跨平台口径，**无需改**。 | 否（已正确） |
| `docs/known-issues.md` | 若有「写方角色 shell 名」相关条目需同步。 | 待总控查 |
| 台账 `GAP-025`② 状态 | 本步是其「独立第一步」，宜在台账记一笔进度（状态/子步）。 | 交总控（台账是总控职责，且子代理改台账须授权） |
| 台账 `GAP-028`（若有跨平台/shell 名相关条目） | 待总控核对是否需状态更新。 | 交总控 |
| `.claude/hooks/self-test.ps1` 的 `F1`/`F2` | 若判据硬编码 `PowerShell`，需同步为「有任一 shell」；**改它须过 `falsifier`**。 | 否（本轮不动 `.ps1`） |
| `record.md` / 进度页 | 总控职责，本子代理不写。 | 否 |

### 4.2 待总控代跑命令清单（本子代理无 shell，无法自跑）

**编号跨分支并集确认（提交前必做，纪律 1 / `AGENTS.md` §6.1）**：
```bash
# 逐 ref 列 docs/changes/ 并集，确认 004 未被占
for ref in $(git for-each-ref --format='%(refname)' refs/heads refs/remotes); do
  echo "=== $ref ==="
  git ls-tree -r --name-only "$ref" -- docs/changes/
done
# 期望：并集中无 004-*（若有，rename 本文件后再提交）
```

**文本级复测（可选，本子代理已用 Grep 跑过，总控可复跑对照）**：
```bash
git -C "$REPO" grep -n "^tools:" -- .claude/agents/        # 13 行含 Bash，2 行 Read,Grep,Glob
git -C "$REPO" grep -n "tools:.*PowerShell" -- .claude/agents/   # 零命中（期望）
git -C "$REPO" grep -n "本机（Windows）shell 名为" -- .claude/agents/  # 零命中（期望）
```

**挂载事实核验（核心，`tools` 声明≠挂载事实）**：
派写方探针（如 `biz-strategist`），令其自报工具清单并跑：
```bash
pwd; echo probe-ok; echo "exit=$?"
```
期望 stdout 含绝对路径 + `probe-ok` + `exit=0`。同时派只读探针（`falsifier`）对照，应回「没有 shell 工具，无法执行」。

**`self-test.ps1` 读数（看 F1/F2 是否仍绿）**：
```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/self-test.ps1
# 或本机无 pwsh 时，待 Go CLI 阶段；本轮若跑不了，标 [未能验证]
```

**提交（本子代理不自己 commit）**：
```bash
git -C "$REPO" add .claude/agents/*.md .claude/agents/README.md docs/changes/004-cross-platform-tools.md
git -C "$REPO" commit -m "fix(agents): 写方角色 tools 跨平台适配 PowerShell→Bash (Linux 迁移)

本机已迁 Linux (bash 5.3, 无 pwsh); 13 个写方角色 frontmatter tools 的
PowerShell 在 Linux 被静默丢弃, 写方失去 shell. 按本机实测改为 Bash,
正文'本机(Windows)shell 名为 PowerShell'断言泛化为跨平台表述.

- 13 写方 frontmatter: PowerShell → Bash
- frontend-dev/contract-dev/ssot-scribe 注释 + ssot-scribe:17-18,46 泛化
- README.md:29 泛化; :56 历史快照不改, 其后加 2026-10-28 补注
- 只读角色 (falsifier/gate-auditor) 围栏表述不动 (跨平台通用)
- 不改 .claude/hooks/*.ps1 (留待 Go CLI 阶段, GAP-025②)

关联: 路线图 P1.2 / GAP-025② (独立第一步)
验证: Grep 文本级 (13 写方含 Bash, 写方 frontmatter 零 PowerShell, 只读围栏保留);
挂载事实核验 + self-test F1/F2 读数交总控代跑 (本子代理无 shell)
详见 docs/changes/004-cross-platform-tools.md"
```

> 提交信息里 `关联:` 与 `验证:` 行如实标注哪些是本子代理跑了的、哪些交总控——
> 不把「没跑到」说成「已实测」（`ssot-scribe.md:52-55`）。

## 五、回填（改动落地后，Grep/Read 复测，2026-10-28）

> **本子代理无 shell，下列为 Grep/Read 文本级核验**（非命令行为验证；「声明 vs 挂载事实」之别见 3.2）。

| 判据 | 工具 | 实测结果 |
| --- | --- | --- |
| 13 写方 frontmatter 全 `Bash` · 2 只读仍 `Read, Grep, Glob` | `Grep "^tools:"` | **15 行**：13 行 `…, Bash`（backend-dev/biz-strategist/contract-dev/data-engineer/finops-controller/frontend-dev/pm-spec-driver/qa-validator/rca-investigator/sec-auditor/sre-operator/ssot-scribe/system-architect）+ 2 行 `Read, Grep, Glob`（falsifier/gate-auditor）✓ |
| 写方 frontmatter 不再含 `PowerShell` | `Grep "tools:.*PowerShell"` | **零命中** ✓ |
| scope B/C 旧断言原句已清除 | `Grep` 三句（「Bash 在本机解析不了」「有 shell（本机 \`PowerShell\`）」「本机（Windows）实测挂载名是」） | **零命中** ✓ |
| 只读围栏表述保留（scope E） | `Grep "PowerShell"` 全文 | `falsifier.md:10,22` / `gate-auditor.md:10,22`「刻意不列 `Bash`/`PowerShell`」**未误改** ✓ |
| README 历史快照未改写（scope D） | `Read` README.md:55-64 | 「回报工具清单 = `Read, Write, Edit, Grep, Glob, PowerShell`，并真跑了命令」（原 `:56`，scope C 加一行后移至 `:57`）**原文不动** ✓ |
| README `:29` 已泛化 · 补注已加 | `Read` README.md:28-34, 62-64 | `:29`「Windows 为 `PowerShell`、Linux/macOS 为 `Bash`（本机现 Linux…）」；`:63-64` 为 `2026-10-28` 补注 ✓ |
| 剩余 `PowerShell` 全为预期保留 | `Grep "PowerShell"` 全文 13 处 | 跨平台映射（ssot-scribe/contract-dev/frontend-dev `:9` 等）· README 历史快照 `:57` · 补注 `:64` · 只读围栏 4 处——**无未预期残留** ✓ |
| ssot-scribe 三处正文已泛化 | `Read` ssot-scribe.md:9-11, 17-19, 47-49 | 注释 / `:17-19` 解析口径 / `:47-49` 路径核验命令（补 `test -f`，注 Windows 用 `Test-Path`）✓ |

**读法（不夸大）**：以上 Grep/Read 只证明**文本改对**——13 写方 frontmatter 的 `PowerShell` 已全部换为 `Bash`、
旧本机断言已泛化、只读围栏与历史快照未误伤。**它们不证明** Claude Code 在 Linux 上真的把 `Bash` 挂载给写方子代理——
那是**声明 vs 挂载事实**之别（`README.md:28-36`），须总控派写方探针自报工具清单并跑最小命令回灌 stdout 才算实测
（见 3.2 / 「四」待代跑命令）。**本节标 `[文本级·已实测]`；挂载事实标 `[未能验证]`。**

**未做（边界，如实）**：
- 未跑 `self-test.ps1` 的 `F1`/`F2`（本机无 `pwsh`，且本轮不动 `.ps1`）——若其判据硬编码 `PowerShell`，改后会红；
  属下游同步（见 4.1），**不是本改动错了**。
- 未跑 `git ls-tree` 跨分支并集（本子代理无 shell）——`004` 取号待总控代跑确认。
- 未派写方探针核验挂载事实——交总控。
