# 001 · 克隆后首次接入引导（文档层）

- **日期**：2026-10-25（UTC）
- **分支**：`feat/onboarding-first-run`（自 `main` `45cc9fe` 切出）
- **关联**：issue #55
- **性质**：文档层改动——**不改任何判据脚本**（`.claude/hooks/*.ps1` 属第 2 个提交单元）
- **记录方式**：**先写后填**。本次改动前先立本条；下方的实测结果于提交前回填。

---

## 一、为什么要改

框架目前只有 `README.md` §十二「怎么用」与 `docs/adopting.md`（**把框架嵌进已有项目**）两个入口，
**没有回答「clone 下来第一步做什么」**——于是新用户与 AI 都缺一个**可观测的接入动作**：

- 用户不知道「业务仓放哪」，AI 也不知道「本工作区到底有没有业务仓」；
- `AGENTS.md` §9.0 的第 2 步要求「判进度」，但**判完只写进 `memory.md`**——
  业务事实被装进**框架仓的运行态**，既违背多仓归属，也没有交给用户的产物；
- 「AI 正在理解」与「AI 已开工」在观测上同形（与 D3 同源的「静默地错」）。

故本次做三件事：**给出接入路径** · **把「判进度」变成落盘产物（现状基线）** · **让 AI 先声明它在理解**。

## 二、改了什么（逐文件）

| 文件 | 改动 |
| --- | --- |
| `ONBOARDING.md`（新增） | 按需读的接入引导：两条路径（A 克隆+挂业务仓 / B 嵌入已有项目 → 指针）· 路径 A 三步 · 开场白 · **现状基线六节模板** · 「读完即止」 · 提 issue 入口 |
| `ONBOARDING.en.md`（新增） | 同构英文版（`^#{2,3} ` 计数与中文版一致，见第三节）；含判据词 `attach check` / `status baseline` |
| `AGENTS.md` §9.0 | ① 五步表**前**加「**0 步 · 接入确认**」（按工作区模式判定；框架自开发模式**不提醒**，避免本仓每轮误报）② 第 2 步判据列追加「**必须落盘**为 `<业务仓>/docs/planning/baseline-YYYYMMDD.md`」③ 五步表**后**加「**开场白**」引用块 ④ 加「**多仓归属**」引用块（框架仓不装业务状态 / 跨仓引用是幻影引用） |
| `AGENTS.en.md` §9.0 | 上述四处**逐条对照翻译**，未放宽任何一条硬约束 |
| `CLAUDE.md` / `GEMINI.md` | 启动自检各加**第 7 条「业务仓接入」**，两处文字一致；**未新增 `##` 章节**（守瘦入口红线 `AGENTS.md:84-86`）；**未写成 `@ONBOARDING.md`**（那会变成常驻导入） |
| `README.md` / `README.en.md` | §八文件地图在 `NOTICE` 行后加两行；§十二「怎么用」开头加指针行 |
| `docs/adopting.md` | **正文一行不动**，头部引用块追加一行互指（指向 `../ONBOARDING.md`） |

**未改**：`.claude/hooks/self-test.ps1`（第 2 个单元）· `docs/ledger.md` · `memory.md` · 任何格数陈述。

## 三、怎么验证

### 3.1 正向实测（已跑，真实输出）

| 判据 | 命令 | 实测结果 |
| --- | --- | --- |
| 章节数相等（未来 C1 的口径） | `Select-String -Path ONBOARDING*.md -Pattern '^#{2,3} '` | 中文 **6** / 英文 **6** |
| 体量可控 | `(Get-Content ONBOARDING.md).Count` | 中文 **71** 行 / 英文 **71** 行（< 120） |
| 判据词存在 | `Select-String -Pattern '接入确认'` / `'现状基线'` | 中文 **1** / **2** 处 |
| 判据词存在（英） | `Select-String -Pattern 'attach check'` / `'status baseline'` | 英文 **1** / **2** 处 |
| 不破坏既有格数、不引入回归 | `powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/self-test.ps1` | 提交前实跑，结果见下方「回填」（第 1 单元 40 PASS / 0 FAIL；第 2 单元**加五格**后 43 PASS / 2 FAIL；第 3 单元收尾 **45 PASS / 0 FAIL**） |
| 编号未撞车（跨全部 ref 并集） | `git ls-tree -r --name-only <ref> -- docs/changes/` × 全部 ref | `docs/changes/` **此前不存在**（`Test-Path` = False），并集为空 ⇒ 取 `001` |

### 3.2 负向 / 待验证（本单元**未建**判据，如实标注）

- **C1（双语章节数比对）与 C2（判据词锚点）尚未机械化**——它们是**第 2 个提交单元**的内容。
  本单元只按未来口径**人工实测**了上述计数（3.1），**不等于判据已存在**。
- **「业务仓接入」第 7 条无守卫**：它是**提示词**，没有任何 hook 检查它是否被执行——
  与 `AGENTS.md` §9.0「本节的机械程度（如实）」同族（`GAP-017`）。
- **「框架自开发模式不提醒」的反例未构造**：本轮只在**本仓（框架自开发布局）**下确认了
  `git rev-parse --show-toplevel` = 仓根、根下即框架文件；**未**在「存在业务仓」的工作区实测提醒分支。

### 3.3 回填（提交前实跑结果，2026-10-25T17:58Z 前后）

`powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/self-test.ps1` → **exit 0**：

```
  PASS = 40
  FAIL = 0
```

其中与本单元直接相关的格（原样摘录）：

```
  PASS  C1 AGENTS 双语章节数相等（zh=33 en=33）
  PASS  C1 README 双语章节数相等（zh=26 en=26）
  PASS  C3 Markdown 表格列数一致（110 张表）
  PASS  D1 CLAUDE.md 与 GEMINI.md 章节数相等（4/4）
  PASS  C6 全仓格数【总数】陈述一致（实际 40；文中出现 40）
```

**读法（不夸大）**：这四格只证明**结构没被弄坏**（标题数、表格列数、瘦入口章节数、格数陈述）。
它们**不证明** `ONBOARDING` 的双语内容等价——那要等第 2 单元的 C1/C2 扩到 `ONBOARDING*.md` 才有机械面；
本单元的双语等价是**逐条对照翻译**的**人工**结论（见 3.2 的如实标注）。

## 四、下游同步（本次已做 / 待做）

- [x] `AGENTS.md` ⇄ `AGENTS.en.md` 同轮同步（结构一一对应）
- [x] `README` 双语文件地图与「怎么用」指针
- [x] `docs/adopting.md` 头部互指
- [x] `CLAUDE.md` / `GEMINI.md` 启动自检第 7 条
- [ ] **`docs/ledger.md`**：本次**未登记 GAP**——本单元是**已批准方案的实施**，
      不新增缺口；第 2 单元若发现判据的残余弱点，再按 §6 登记（需授权）
- [ ] **进度页 / `record.md`**：属**总控**职责，本子代理**不写**

## 五、第 4 单元 · qa-validator 独立测试发现的缺陷修复（`2026-10-25`，issue #55）

**改动面**：`.claude/hooks/self-test.ps1`（`C6` 分母 · `D4` 两处）· 本文件（「加四格」→「加五格」）·
`docs/guard-self-test.md` / `docs/delivery-gates.md` / `README` 双语（自测耗时读数）。
**格数不变（45）**，**未加 `C2` 锚点**。

| 缺陷 | 修法 | 注入验证（真跑） |
| --- | --- | --- |
| **`C6` 分母把「跳过」当「不存在」**：`$actualCells = Pass + Fail + 1`，`SKIP` 既不进 Pass 也不进 Fail ⇒ 分母变小。真实 `git clone` 里 E 组与 E5 全 SKIP ⇒ **`实际 40 / 文中出现 45`、`39 PASS / 1 FAIL / exit 1`** | 新增 `$script:Skip`；**每个 SKIP 分支按它代表的格数累加**（E 组 4 · E4 1 · E2 1 · E5 1 · F 组 2），分母改为 `Pass + Fail + Skip + 1`；小结加 `SKIP = N` 一行 | 维护者树 **45 / 0 / SKIP 0 / exit 0**；**真实 clone**（仅替换 `self-test.ps1` 为未提交版）**40 / 0 / SKIP 5 / exit 0 / C6 实际 45** |
| **`D4` 假红**：`@[^\n]*ONBOARDING` 无左边界，`a@b.com` 同行提到 `ONBOARDING.md` 即误报 | 左边界收紧为「**行首或空白之后**」的 `@`（`(?m)(^` + 竖线 + `\s)@[^\n]*ONBOARDING`；本表内竖线不便直书，以文字代替） | 注入 `<!-- 联系方式 a@b.com ；接入见 ONBOARDING.md -->` ⇒ **PASS**；注入 `@ONBOARDING.md` ⇒ **FAIL**（`实测：1 / [CLAUDE.md 出现 @ 导入：@ONBOARDING]`） |
| **`D4` 假绿**：指针指向不存在的 `docs/ONBOARDING.md` 仍 PASS | 抽 `ONBOARDING*.md` 的路径段逐个 `Test-Path`，判据取**至少一个可解析**（取舍见脚本注释：叙述性提及与真指针文本上不可分，逐个强判会误报） | 改成 `docs/ONBOARDING.md` ⇒ **FAIL**（`实测：1 / [CLAUDE.md 的 ONBOARDING 指针解析不到真实文件（docs/ONBOARDING.md）]`）；还原 ⇒ **PASS** |
| **进度页 0 步措辞**把三种**布局**当成了两种**模式** | 页面改为「工作区模式（框架自开发 / 业务开发）」，并注明布局（目标 / 自托管 / 带项目）是另一回事（`AGENTS.md` §0.0） | 页面**不入库**（本机排除）⇒ 判据是 `AGENTS.md:771`「**模式只有两种**」的原文对照，非机械格 |
| **三处读数** | 本文件「加四格」→「**加五格**」；`guard-self-test.md` 耗时 `21 s` → **本次实测 `24.5 s` / `26.7 s`**；`delivery-gates.md` / `README` 双语同值同步 | `C6` / `C3` 照绿即证文本改动未破坏结构 |

> **未做的**：`docs/ledger.md`（`GAP-029` 残余③ 状态更新由总控处理）· `ONBOARDING*.md` 正文 · `AGENTS.md` §9.0 正文。
> **未建**：`SKIP` 数**没有独立的负向格**（谁去注入"某个 SKIP 漏计"？）——它的正确性目前靠
> 真实 clone 的读数（`SKIP = 5` 且 `实际 45`）与逐分支注释支撑，属 `GAP-017` 同族，登记交总控裁定。
