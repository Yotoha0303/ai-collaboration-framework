# 未竟事项 · 唯一台账（`docs/ledger.md`）

> **不在本台账里的"还没做"等于不存在**（出处：`AGENTS.md` §6）。收纳 **`GAP-` / `INC-` / `DEFER-`** 三类；`ADR-` 落 `docs/adr/`，`MIG-` 落 `backend/migrations/`（当前无对应物）。本仓为**自托管布局**，故本文件在仓内、属 ✅ 入库；**不引用仓库外文件**——证据的命令与输出**原样抄录在附录**，clone 的人可直接复核。

| 项 | 值 |
| --- | --- |
| 台账快照时间（UTC） | `2026-10-09T14:50:14Z`（实测 `(Get-Date).ToUniversalTime()`） |
| 快照时 HEAD | `ad4e6c8`（全长 `ad4e6c8624e0553f1fe5e940ec83b0dddb891c02`） |
| 快照时入库文件数 | `17`（`git ls-files` 行数实测） |
| 已用 `GAP-` 最大号 | `GAP-009` |
| 已用 `INC-` / `DEFER-` | 无（`0`） |
| 页名指针快照 | `.claude/progress-page.txt` → `project-progress.html`，字节 `112,…,108,10`，SHA256 `BF4B6899…B2ADE1` |

## 一、登记表

**状态取值**：`未解除` / `已解除` / `不适用（该环无对应物）` / `待人工裁定`。**按编号升序，编号不复用、不重号；解除时改状态并加一行留痕，不删原条目。**

| 编号 | 缺口（一句话） | 证据（复跑命令见附录 B） | 解除条件 | 状态 |
| --- | --- | --- | --- | --- |
| **`GAP-001`** | `tools:` 名单里的工具名与**实际挂载名**不一致时**被静默丢弃**，**无报错**——通用风险；本案例已修，但**机制仍在** | 子代理自报工具清单 + `Get-Location; echo probe-ok` 回灌（附录 B.5）：清单 = `Read`/`Grep`/`Glob`/`PowerShell`，`probe-ok`，exit 0。而名单原写 `Bash` → 被丢弃；**本次已改 `ssot-scribe.md` 只写真名**（附录 D.5） | 工具名由**实测**填入而非照抄；核验方法见附录 C.1。**须在每次新增/改动角色 `tools` 时执行** | `已缓解（机制仍在）` |
| **`GAP-002`** | 进度页守卫**双静默**：`.claude/progress-page.txt` 一改错，「缺页静默」与「SHA 判据」**同时失效**（二者共用同一个 `$name` 与同一套路径推导）；**且「缺页静默」与「死代码」在观测上等价**（五种因果不可分） | 攻击 A（2026-10-09 实跑复现，**附录 D.1**）：把指针指向不存在的页名（页实为存在、含错 SHA）→ 守卫 **stdout 空、静默放行** | 让「指针**存在但读不出页名**」与「页**确实缺失**」**分别处置**；改后重跑附录 C.2 的两个用例 | **`已缓解`**（残余见下） |
| **`GAP-003`** | 守卫**误报**：页面写 **40 位完整 SHA** 时，与 **7 位短 SHA** 做**字符串全等**比对，被判为「落后」 | 攻击 B（2026-10-09 实跑复现，**附录 D.2**）：页面写 `<div>head <b>3b9030ff…6b6f72</b></div>` → 守卫 emit `decision:block`（**误报**：内容其实一致） | 改为**前缀比对**，改后重跑用例 | **`已解除`**（附录 D.3 实测） |
| **`GAP-004`** | **自托管布局下，`AGENTS.md` §5「入库策略」的"保障方式：位置，而非忽略规则"论证不成立**——框架文件已被 `git ls-files` 跟踪 | `git ls-files` 共 **16** 个文件，其中**含框架全部文件**（附录 B.2） | 人工裁定后同步改写 §5 表格与 §0.0 提示（二选一：**接受"本仓即框架"**，或**把仓库拆为子目录**） | **`已解除`**（**裁定：采纳"本仓即框架"**，附录 D.4） |
| **`GAP-005`** | **只读围栏修复后引入的新缝隙**：`falsifier` / `gate-auditor` 的执行改由**总控代跑**，但「**代跑是否真的发生**」**没有判据**——代跑缺失时，其产物会停在 `无法判定`，**与"确实没有 shell"外观相同** | 围栏修改本身（附录 B.5）；**无可跑命令能区分二者**——这正是指缝的性质 | 需要一个把「代跑」**投影到留痕**的机制（如：每次代跑强制在运行态记录里留一行，且该行可被机械核验） | `未解除（部分缓解）`（最小锚见下） |
| **`GAP-006`** | 本工作区**尚无 CI / 合约 / 前端等对应物** → `AGENTS.md` §7 部分复核命令属**模板**、当前无对应物。**这不是缺口，而是"该环无对应物"**；按 §7 口径**登记备查** | `Test-Path .github` → `False`；`Test-Path Dockerfile` → `False`；`Test-Path docs` → `False`（登记本表之前） | **接回该环时解除**（届时 §7 对应行从"模板"转为"待实测"） | `不适用（该环无对应物）` |
| **`GAP-007`** | 守卫的**仓库解析顺序**把 `project/` 排在**工作区根之前**——`project/` 目录**存在但非仓库**时，一旦有人在其中 `git init`，守卫会锁定该**内层空仓** → 取不到 HEAD（unborn，`rev-parse` exit 128）→ **永久静默**，而静默正是它正常时的表现 | 对照实算（附录 D.6）：同一假 `.git` 下，**旧序**解析到 `…\project`，**新序**解析到工作区根；`git -C <新建空仓> rev-parse --short HEAD` → 空输出、**exit 128** | 候选顺序**对调**（优先工作区根），**保留两处候补**；改后重跑附录 C.2 用例 | **`已解除`**（**已独立放行**：`falsifier` 设计攻击、总控代跑 T1 + T10，两方向实测，附录 D.7） |
| **`GAP-008`** | 守卫用**双向前缀**比对 SHA（`:150` `$head.StartsWith($recorded) -or $recorded.StartsWith($head)`），故「**真前缀 + 假后缀**（至 40 位）」被判为一致 → 放行伪造 SHA | 代跑实测（`record.md` `[2026-10-09T14:48:43Z]` 负向 T5，附录 D.7）：页写 `ad4e6c8000000000000000000000000000000000`（真前缀 `ad4e6c8` + 假后缀）→ 守卫 **stdout 空、静默**，本该认出"这不是 HEAD" | 若需覆盖：把"页长 > 7 且 ≥ 前缀"的**歧义**情形改判为不静默；**判定前须人工裁定**（可能得不偿失，见右侧边界） | `已修（二次修复：--verify 须降级 EAP）` |
| **`GAP-009`** | 守卫判仓库用的是 `.git` 的**存在性**而非**有效性**（`:133` `Test-Path (Join-Path $_ '.git')`）：若 `project/.git` 是**空目录**（非有效仓），被选中即 `rev-parse` 失败 → 静默 | **潜在、当前布局不可达**：实测 T3 **BLOCK**（`record.md` `[2026-10-09T14:48:43Z]`，附录 D.7）—— 新序 `@($ws, project)` 令 `$ws` 先命中，**空目录根本不被咨询**；`falsifier` 预测"静默"**被实测推翻**。仅**目标布局**（工作区根无 `.git`、仓真在 `project/`）下可达。**该性质属 `:133` 既有，非本轮引入** | 接回目标布局时改为校验 `.git` **有效**（如 `git -C <cand> rev-parse --git-dir` 成功才采纳），而非 `Test-Path` | `修复待独立放行` |

> **附注（`GAP-009` 同源，一行）**：`AGENTS.md` 把 `$REPO` 指向 §0.0 的 `git rev-parse --show-toplevel`，而该命令**只向上找**——在**目标布局**（仓在 `project/` 子目录）下**报错**。
> 即 hook 的解析规则与文档声明的规则**在目标布局下不一致**（D4 类：两处不同成熟度的规则）。

**`GAP-008` / `GAP-009` 修复留痕**（`2026-10-09T15:51:54Z`，实现侧口径 · **放行待 `falsifier`**，命令与 stdout 另见 `record.md` 同轮行）：
- **`GAP-008`**：`:150` 双向前缀比对 → **两侧各解析为完整 commit id 再比**（`rev-parse HEAD` vs `rev-parse --verify --quiet "<sha>^{commit}"`，`$recorded` 先 `.ToLower()`）；正则同时改**大小写不敏感**（`[0-9a-fA-F]{7,40}`）。
- **`GAP-009`**：`:133` 候选判据由 `.git` **存在性**改为「存在 **且** `git -C <cand> rev-parse --git-dir` 成功」；**两处候选保留**。
- **关键实测（刻意的实现细节，不是美化）**：① **裸形式在本机 PS 5.1 下反而不工作**——`$ErrorActionPreference='Stop'` 把 git 写 stderr 的**非零退出**升格为**终止错误**，被外层 `catch { exit 0 }` 吞掉 → **又回到静默**（`--git-dir` 那条实测 C10 = 静默）。故**新增的两处 git 调用各自套了作用域内 `$ErrorActionPreference='Continue'`**（`--verify` 处另加 `--quiet`）。② **`$recorded.ToLower()` 在本机 git 2.49.0 下是否必需未能证伪**——`rev-parse --verify "AD4E6C8^{commit}"` **本来就成功**（不区分大小写），保留它只为对 git 内部 hex 口径**显式归一**。

**`GAP-008` 二次修复留痕**（`2026-10-09T16:03:11Z`，实现侧口径 · **放行待 `falsifier`**）：**首修已被独立复核击穿**——`falsifier` 设计的 **T2**（页写一个**存在的非 commit 对象** id，如 `HEAD^{tree}` 的 40 位）实测**静默**，本该 BLOCK。**根因**：`:161` 的 `--verify "<sha>^{commit}"` 在对象类型不符时失败，**`--quiet` 挡不住**——外层 `Stop` 把 git 写 stderr 的非零退出升格为终止错误，被最外层 `catch { exit 0 }` 吞成静默；**同 `:136-139`，上一轮只修了那一处、漏了这里**。**本次**给 `:161` 套上同形的**作用域内 `$ErrorActionPreference='Continue'`**（`:160` 的 `rev-parse HEAD` 不动——此处仓库已校验过）。
> **`GAP-008` 边界（`falsifier` 指出，一行）**：正则 `{7,40}` **假定对象 id ≤ 40 位**；`--object-format=sha256` 的仓（**64 位** id）下**即使页面写的是完全正确的 SHA 也永不匹配** → 走「无标记静默」（**永久静默**）。本仓为 **sha1，不影响**；该边界**非本次引入**。

**`GAP-002` 残余（已接受的代价）**：**指针指向不存在的页名**时仍静默——它与"页确实缺失（尚未初始化）"在观测上**不可分**，故**不报**（理由见 `AGENTS.md` §5）；**缓解后新行为**：指针**存在但读不出页名**（空 / 全空白 / 不可读）→ emit `systemMessage`。

**`GAP-003` / `GAP-004` 解除留痕**：两条动作**均已落地**，实测见**附录 D.3 / D.4**。**D3 判据不得自审**——改判据者（实现方）不得自放行，故 `GAP-003` 的「`已解除`」是**实现侧口径**，独立复核须**另派只读方**（`falsifier`）补记。**不删原条目**：已发生的事实是**证据链**，不是待办事项。

**`GAP-001` 缓解留痕**：① `.claude/agents/ssot-scribe.md` 的 `tools:` 改为 `Read, Write, Edit, Grep, Glob, PowerShell`（**只列本机实测名**，不再同列 `Bash`），同处注释写明**换机须按实测改**；② `falsifier.md` / `gate-auditor.md` 仍为 `Read, Grep, Glob`（**未加任何 shell**）。**残余（故标"已缓解"非"已解除"）**：**声明与挂载不一致时仍不报错**（harness 行为，本框架改不动）；核验**靠人工规程**（附录 C.1），**不是机械判据**——没人跑 C.1 时，写错的名字会**一如既往地静默**。

**`GAP-005` 最小锚（未解除 · 部分缓解）**：**每次代跑，总控必须在运行态记录追加一行**（**命令原文 + 真实 stdout 摘要**）——据此可审计：派发的只读角色数 vs 代跑行数，缺代跑会**对不上账**。**局限（不得读成"已解决"）**：① **非实时强制**（harness 层无钩子，只能事后发现）；② 判据**依赖总控自己写那一行**——不写时「**没代跑**」与「**没派过只读角色**」都表现为无行，**不可分**；③ 锚的痕迹**在本台账之外**（运行态记录不随本仓分发），故本条**只登记"要求"**，审计须在运行态记录所在工作区做——**不声称台账自包含**。

**`GAP-007` 修复留痕**：`.claude/hooks/check-progress.ps1` 的 `$repo` 候选**顺序对调**为 `@($ws, (Join-Path $ws 'project'))`，**保留两处候补**（fail-closed 脚本的回退不得删）。**顺带抓到一处文实不符**：文件头早已写「workspace root **always wins** if it holds `.git`」，而代码先把 `project/` 排在前面（**头注释描述的是修好之后的行为，代码没兑现**）；本次把代码改到与头注释一致并重写该处行内注释。改后逐案复跑见**附录 D.6**。

**守卫边界留痕（`GAP-007` / `008` / `009`）**：**`GAP-007` 已独立放行**——`falsifier` 设计攻击、总控代跑，**两方向实测**（附录 D.7）：**T1**（`project/` 内 `git init` 空仓 + 页写错 SHA → **BLOCK**，未被内层仓劫持）+ **T10**（移除 `project/` + 页写错 SHA → **BLOCK**）。
**`GAP-008` / `GAP-009` 为两条新边界**（证据同 D.7 的 T5 / T3）。**`GAP-008` 的边界（必须读，否则会被读成严重漏洞）**：**正常写作流程不会产生它**——页要么写 **7 位真短 SHA**、要么写 **40 位真全 SHA**，触发前提是"**页已被写错**"，即守卫本要抓的那种状态；故列为**已知边界**，**不是回归**。**`GAP-009` 如实标"潜在、当前不可达"**：`falsifier` 预测"静默"，**实测 T3 为 BLOCK，预测被推翻**；该洞仅**目标布局**可达，且属 `:133` 的**既有性质，非本轮引入**。
> **本段已被后续修复取代（补记，不删）**：`GAP-008` / `GAP-009` **均已改判为 `修复待独立放行`**（见上「修复留痕」）。**`GAP-008` 不再是"已知边界"**——上述「正常写作流程不会产生它」的论证**只说明它不是回归，不说明不可修**，本轮已修。**`GAP-009` 的"当前不可达"亦不再成立**：新增的沙箱实测（`ws/.git` 为**悬空 gitfile**，`project/` 为真仓）使该候选路径**可达**，旧判据实测**静默**、新判据**BLOCK**——即**洞可达、已修、待独立放行**。

## 二、附录 A · 登记前检索留痕（**撞车检查**）

`AGENTS.md` D4：**登记新编号前必须先全仓检索**——**撞车比漏登记更糟**。以下为**首次登记前**在仓库内实跑的检索，命令与真实输出原样抄录。

```
$ git grep -n "GAP-"
AGENTS.md:149:- 标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）· `INC-`（线上故障）· `DEFER-`（延期债务）。
AGENTS.md:456:| `GAP-` | 质量缺口 | `"$REPO"/docs/`（唯一台账） | **任何"还没做"必须在此，否则它不存在** |
README.md:70:标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）·
prompts/全生命周期工程质量总监与系统架构师.md:16:   - 全局标识符严格定义：ADR-（架构决策）、MIG-（数据库迁移）、GAP-（质量缺口）、INC-（线上故障）、DEFER-（延期债务）。
prompts/全生命周期工程质量总监与系统架构师.md:30:- 07 排障：准出 = 故障复盘具备秒级时间线与对照实验 + 根因直接回写产品与架构文档 + 改进项全部转为 GAP-xx 台账。
exit=0
```

**5 处命中全部是"标识符定义/规则陈述"，无任何已用编号。** 同法检索 **`GAP-[0-9]`（带数字的具体编号）** → **零命中**（`exit=1`）。
> `exit=1` 是 `git grep` 的"零命中"约定，不是错误。故首次登记从 `GAP-001` 起，**不撞车**。

> ⚠️ **口径声明（一句）**：`git grep` **只搜已入库文件**（看不到未入库与被 `.gitignore` 掉的路径），故零命中**不等价于**全盘 `Grep` 的零命中——两种口径的差异**必须明说**；本次检索时本文件尚未入库，不影响结论。

### A.2 新增 `GAP-008` / `GAP-009` 的登记前检索（2026-10-09，实测）

```
$ git grep -n "GAP-[0-9]" -- AGENTS.md README.md CLAUDE.md .claude    # 去掉本台账后的命中：
.claude/hooks/check-progress.ps1:25:# IS the repo, so the framework files sit in the repo by design (GAP-004: the
.claude/hooks/check-progress.ps1:105:    # silent fallback this replaces is the GAP-002 defect.
.claude/hooks/check-progress.ps1:146:    # PREFIX, not equality (GAP-003): the page may carry the 40-char SHA or a
AGENTS.md:313:> **本仓即框架**（人工裁定，见 `"$REPO"/docs/ledger.md` 的 `GAP-004`）：本仓库**就是框架自身的仓**，
AGENTS.md:402:> 残余风险见台账 `GAP-002`。
README.md:163:> 这是**显式分工**，不是降级；但它引入了一条新缝隙，**已登记为 `GAP-005`**
exit=0

$ git grep -n "GAP-008"   -> （无输出） exit=1     ← 零命中
$ git grep -n "GAP-009"   -> （无输出） exit=1     ← 零命中
$ git grep -n "GAP-010"   -> （无输出） exit=1     ← 零命中
```

**读法**：**除本台账外**共 **6 行**命中，**全部是引用既有编号**，最大号只到 `GAP-005`；本台账当时登记到 `GAP-007`。三条拟用编号均**零命中**（`exit=1` 是零命中约定，不是错误）⇒ 新号从 **`GAP-008`** 起，**不撞车**（D4）。

## 三、附录 B · 证据抄录（**自包含，不依赖仓库外文件**）

### B.1 仓库根的解析（布局判据）

```
$ git rev-parse --show-toplevel
D:/MyDocuments/ai-collaboration-framework
exit=0
```

**仓库由含 `.git` 识别，名字任意**——**判据是 `.git` 在谁身上，不是 `project/` 在不在**（`AGENTS.md` §0.0）。
本行在 `project/` 出现前采集（`Test-Path project` → `False` 是彼时事实）；采集后 `project/` 已被人工建出（内含 `README.md`、**无 `.git`**），是**外部项目目录**、不入本仓（挡在 `.git/info/exclude`，见附录 D.6）。

### B.2 `GAP-004` 的证据：框架文件确已被跟踪

```
$ git ls-files | wc -l
16

$ git ls-files
.claude/agents/README.md
.claude/agents/falsifier.md
.claude/agents/gate-auditor.md
.claude/agents/ssot-scribe.md
.claude/hooks/check-progress.ps1
.claude/progress-page.txt
.claude/settings.json
.gitattributes
AGENTS.md
AI_tools/start_claude.bat
CLAUDE.md
README.md
prompts/AI协同工程架构.png
prompts/AI总控.md
prompts/全生命周期工程质量总监与系统架构师.md
prompts/角色契约.md
exit=0
```

其中 `AGENTS.md` / `CLAUDE.md` / `prompts/*` / `.claude/*` 正是 §5 表格里原标「❌ 不入仓库」的**框架文件与运行态**，它们**确实在仓库里**。**补充实测**：`Test-Path .gitignore` → `False`（本仓**无 `.gitignore`**）。

### B.3 `GAP-006` 的证据：该环无对应物

```
$ Test-Path .github      → False
$ Test-Path Dockerfile   → False
$ Test-Path docs         → False      （登记本表之前）
$ Test-Path project      → False      （预期：自托管布局）
```

### B.4 写死占位名的可跑性对照（实测）

```
$ git -C project status --porcelain
fatal: cannot change to 'project': No such file or directory
exit=128

$ git -C "$REPO" status --porcelain          # $REPO = git rev-parse --show-toplevel
（正常输出工作树状态）
exit=0
```

写死 `project` 时得到的是**「命令没跑」**，**不是**「围栏有效」——**不得**混为一谈（D1）。

### B.5 `GAP-001` / `GAP-005` 的证据：工具挂载与围栏

```
$ Get-Location; echo probe-ok
D:\MyDocuments\ai-collaboration-framework
probe-ok
LASTEXITCODE=0
```

子代理**自报**的工具清单 = `Read` / `Grep` / `Glob` / `PowerShell`（本机 shell 挂载名为 **`PowerShell`**，**不是** `Bash`——`Bash` 在本机解析不了、被**静默丢弃**）；只读角色的 `tools` 一行见**附录 D.5** 的 `git grep` 实测。

**为何去掉 shell**：仅去掉 `Write`/`Edit` **挡不住写**——**shell 本身就是写后门**（`Set-Content` / `Out-File` / `Remove-Item` 都能落盘、能删文件），故**两个都去掉**；**代价**是只读角色**跑不了命令**，执行**交总控代跑**——这**正是 `GAP-005` 的来源**。

## 四、附录 C · 可复跑的核验命令

### C.1 `GAP-001` 的工具挂载核验（**改任何角色的 `tools` 后必跑**）

1. 派一个子代理，令其**自报可用工具的确切名字**，并跑 `Get-Location; echo probe-ok`。**判据**：`probe-ok` 出现 **且** `LASTEXITCODE=0` → 该会话**确实有 shell**，工具名以**自报清单**为准（本机实测为 `PowerShell`）。**名单是声明，挂载才是事实；两者不一致时无声。**

### C.2 进度页守卫的用例（**改页名后必跑**）

```powershell
# 用例① 缺页（页面不存在）-> 必须【静默 exit 0】（"尚未初始化"，放行是对的）
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例② 注入错误 SHA（页面【存在】）-> 必须 emit {"decision":"block"}
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例③ 指针文件存在但为空 -> 必须 emit {"systemMessage":…}   （GAP-002 缓解后的新分支）
# 用例④ 页面写 40 位完整 SHA（同一提交）-> 必须【静默】        （GAP-003 修复后的回归）
# 用例⑤ 在 project/ 下造一个假 .git，同一页面同一错 SHA -> 必须**仍然** emit block
#        （GAP-007 修复后的回归：内层空仓不得劫持守卫）
```

> ⚠️ **必须同时跑②与①**：只验「一致时静默」**不够**（D3）——它区分不了「正常」与「死代码」；缺页分支与死代码**在观测上等价**（`GAP-002`），**只有 ② 仍有牙，才能反推 ① 的静默是"确无判据"。**
> 跑完**务必清理**临时页面，并复核指针文件字节未被改动（`status --porcelain` 应干净）。**实测读数见附录 D.3 / D.6**。

### C.3 本台账自身的登记规程

1. **先检索** `git grep -n "GAP-[0-9]"`，确认拟登记项未被既有编号覆盖；
2. **取号** = 本文件「已用 `GAP-` 最大号」+1，**不得复用、不得跳号**；
3. **写一条**：补齐「缺口 / 证据 / 解除条件 / 状态」四列；
4. **同步快照**：更新顶部「快照时间 / HEAD / 入库文件数 / 最大号」；
5. **改状态**：解除时改状态并**补一行留痕**，**不删原条目**。

## 五、附录 D · 守卫实测（**真实 stdout，2026-10-09 由台账维护方实跑**）

> **口径声明（一句）**：本节输出均为**本次实跑**所得，非转述、非推断；但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**独立放行，独立复核须**另派只读方**。

**D.1 攻击 A —— 指针指向不存在的页名（`GAP-002` 实证）**。**前置**：进度页**存在**，状态条写错 SHA `0000000`（当时 HEAD 为 `3b9030f`）。

```
$ # 把 .claude/progress-page.txt 改为 'no-such-page.html'
$ powershell -NoProfile -ExecutionPolicy Bypass -File ".claude/hooks/check-progress.ps1"
（stdout 空）
guard exit=0

--- 对照：指针还原为真实页名 project-progress.html，同一页、同一错 SHA ---
{"decision":"block","reason":"进度页落后于仓库：project-progress.html 记录的 HEAD 是 0000000，而当前是 3b9030f。…"}
```

**读法**：同一页面、同一错 SHA，**只因指针里的页名不同**（静默放行 vs 正常阻断）⇒ **指针文件是唯一开关**，一错则两分支**同时失效**（`GAP-002` 成立）。

### D.2 攻击 B —— 页面写 40 位完整 SHA（`GAP-003` 实证，**修复前**）

```
$ Set-Content project-progress.html -Value "<div>head <b>3b9030ff76f8e56dc787658578b801795c6b6f72</b></div>"
$ powershell … -File ".claude/hooks/check-progress.ps1"
{"decision":"block","reason":"…记录的 HEAD 是 3b9030ff76f8e56dc787658578b801795c6b6f72，而当前是 3b9030f。…"}
```

**读法**：页面写的 SHA 与 HEAD **指的是同一个提交**，守卫却判「落后」⇒ **字符串全等是误报源**。

**D.3 修复后复跑（`GAP-003` 解除 / `GAP-002` 缓解的实证）**。修复 `.claude/hooks/check-progress.ps1` 后，逐案复跑（页存在时皆用默认页名）：

```
CASE-1 页不存在 + 指针正常                       -> (empty stdout) exit=0   静默 ✔
CASE-2 指针存在但为空 + 页不存在                 -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-3 指针存在但为空 + 页存在(SHA错)            -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-4 指针存在但全空白                          -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-5 页面写 40 位完整 SHA（同一提交）          -> (empty stdout) exit=0   GAP-003 已修 ✔
CASE-6 页面写错误 7 位 SHA                       -> {"decision":"block",…}   有牙 ✔
CASE-7 指针指向不存在的页名                      -> (empty stdout) exit=0   已接受的代价 ✔
CASE-8 指针文件缺失 + 页存在(SHA错)              -> {"decision":"block",…} ✔
CASE-9 指针文件缺失 + 页不存在                   -> (empty stdout) exit=0   ✔
```

**清理复核**（防"测试留下残留"变成新的静默漂移）：

```
pointer bytes   = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
pointer SHA256  = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1
page exists     = False
git status ptr  = ''            （空 = 指针未被改动）
```

**读法**：`CASE-6` 仍有牙 ⇒ `CASE-1/7/9` 的静默是**确无判据**，而不是"脚本死了"；指针文件**逐字节一致**（无 BOM、无 CRLF）⇒ 未留残留。

> **一次真实险情（如实记录）**：首次复跑时测试脚本自身的 `WriteAllText` 重载**报错中断**，指针文件**停在「空」状态**；已按台账快照的字节序列**逐字节还原**并复核 SHA256 与 `git status`（如上）。**教训**：破坏性用例**必须先备份原值，且清理路径不得在崩溃点之后**——否则"测试"本身就成了新的静默漂移源。

**D.4 `GAP-004` 解除了什么（人工裁定：采纳"本仓即框架"）**。裁定后 `AGENTS.md` 的改写（§0.0 · §5 入库策略 · §5 推送前必做第 2 条 · §0.1）：

| 处 | 改前 | 改后 |
| --- | --- | --- |
| §0.0 | 「框架的**目标布局**是仓库为子目录…自托管布局下『框架在仓库之外』**不成立**」+ 独立的「仓库的识别方式」小节 | 一句话：**仓库 = 含 `.git` 的目录，名字任意；工作区根自身含 `.git` 即仓库本身**（自托管布局），`$REPO` 由 `git rev-parse --show-toplevel` 解析 |
| §5 入库策略 | 框架文件与运行态 = **❌ 不入仓库**；「**保障方式：位置，而非忽略规则**…结构上不可能」 | 两类 = **⬜ 按布局而定**；「**本仓即框架**…同在仓库内是**有意决定**」，两类布局差异收为**一句话** |
| §5 推送前第 2 条 | 「**框架文件围栏**…必须在推送范围内**不存在**」 | 「**推送范围的核对**…框架文件**在**范围内，这是有意决定；仍要核实而非假定」 |

**不拆仓库。** 残余影响（**须继续跟踪**，不随本条关闭）：按 §5 判据，`record.md` / `memory.md` / 进度页等**运行态**在自托管布局下亦属入库，是否**随仓库外发**由发布范围决定——`GAP-005` 与 §5 连带纪律仍指向此处。

### D.5 `GAP-001` 缓解的实测（2026-10-09）

```
$ git -C "$REPO" grep -n "^tools:" -- .claude/agents
.claude/agents/falsifier.md:4:tools: Read, Grep, Glob
.claude/agents/gate-auditor.md:4:tools: Read, Grep, Glob
.claude/agents/ssot-scribe.md:4:tools: Read, Write, Edit, Grep, Glob, PowerShell
```

**读法**：写方（`ssot-scribe`）只列**本机实测名** `PowerShell`，两个只读方**不含任何 shell**（机械只读，未被本次改动放松）。**残余未消**：名单与挂载不一致时**仍不报错**——故本行是 `已缓解（机制仍在）`，**不是** `已解除`；且**本行只是声明侧核对**，挂载实测须另派子代理执行（附录 C.1），**不得**据本行宣称"挂载已验证"。

### D.6 `GAP-007` 的实测：守卫的仓库解析与守卫自身（2026-10-09）

**① 当前布局解析到位**（`project/` 存在、但**无** `.git`）：

```
ws   = D:\MyDocuments\ai-collaboration-framework
repo = D:\MyDocuments\ai-collaboration-framework        <- 新序取到工作区根（自托管）
$ git -C <repo> rev-parse --short HEAD
ad4e6c8
```

**② 危险布局：`project/` 内含一个 `.git`。** 造一个**空** `.git` 目录，同一页面、同一错 SHA，复跑守卫：

```
NEW order (工作区根优先) resolves repo = D:\MyDocuments\ai-collaboration-framework
OLD order (project 优先)  resolves repo = D:\MyDocuments\ai-collaboration-framework\project
```

**③ "取不到 HEAD"单跑复现**（仓库外临时目录，用后即删）：`git init <tmp>` 后 `git -C <tmp> rev-parse --short HEAD` → **空输出、`exit 128`** ⇒ 守卫走到 `if (-not $head) { exit 0 }` ⇒ **静默放行**——与它正常时的静默**在观测上不可分**（即 `AGENTS.md` §8 那类漂移）。

**④ 修复后逐案复跑**（页面存在，逐案注入，`finally` 内逐字节还原）：

```
CASE-2 页存在 + 错 7 位 SHA            -> {"decision":"block",…}                     有牙 ✔
CASE-4 页存在 + 同提交 40 位完整 SHA   -> (empty stdout) exit=0                     静默 ✔
CASE-3 指针存在但为空                  -> {"systemMessage":"进度页指针异常：…"}     ✔
CASE-5 无指针文件 + 错 SHA             -> {"decision":"block",…}                     ✔
CASE-1 project/ 内含空 .git + 错 SHA   -> {"decision":"block",…}    GAP-007 修复后仍拦 ✔
```

**清理与完整性复核**（本仓 `project/` 下**不留** `.git`）：

```
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与攻击前一致）
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
page SHA256    = 993B746055EE02F662C1895509C12B5E19AAE46AD8C1E93E00D17AF3FFDB3E04
project/.git removed = True
$ git status --porcelain
 M .claude/agents/README.md
 M .claude/agents/ssot-scribe.md
 M .claude/hooks/check-progress.ps1
 M AGENTS.md
 M docs/ledger.md
（无 ?? project/ —— 它已被 .git/info/exclude 挡在提交之外）
```

**读法**：`CASE-2/5/1` 仍有牙 ⇒ `CASE-4` 的静默是**确无判据**，不是"脚本死了"；指针文件**逐字节还原**、SHA256 与攻击前一致 ⇒ 无残留。

> **又一次真实险情（与 D.3 同一根因）**：清理代码**再次**踩坑——删掉指针后调 `Resolve-Path` 还原，**该 cmdlet 对不存在的路径直接抛错**，`WriteAllBytes` 未执行 ⇒ 指针一度**缺失**。**修法**：改用**绝对字面路径**重建。**教训升级**：D.3 的（"清理路径不得在崩溃点之后"）**不够**——**真正要守的是「还原步骤本身不得依赖被测对象当前的状态」**；fail-closed 的判据如此，**清理代码同样如此**。

**D.7 `GAP-007` 独立放行 + `GAP-008` / `GAP-009` 边界（`falsifier` 设计攻击 · 总控代跑）**。**口径**：攻击清单由**只读方** `falsifier` 设计、命令由**总控代跑**（只读围栏下无 shell，见 `GAP-005`）——此即 D3「判据不得自审」的落地：**设计攻击者不是写守卫的人**。

```
T1  在 project/ 内 git init（空仓：HEAD 空 / rev-parse exit 128）+ 页写 0000000
    -> BLOCK                       GAP-007 已修：未被内层空仓劫持
T10 移除 project/ + 页写 0000000
    -> BLOCK                       区分"改动正确"与"守卫已死"（D3 要求的反向对照）
T5  页写 ad4e6c8000000000000000000000000000000000（真前缀 ad4e6c8 + 假后缀）
    -> (stdout 空) 静默            GAP-008：双向前缀匹配放行伪造 SHA，实测复现
T3  建 project/.git（空目录）+ 页写 0000000
    -> BLOCK                       **推翻 falsifier 预测**：新序 $ws 先中，空目录不被咨询
                                   ⇒ GAP-009 仅在目标布局可达（潜在、当前不可达）
T6  页写 AD4E6C8  -> 静默          既定边界：正则 [0-9a-f] 不匹配大写（非本轮回归）
```

**还原复核**：指针 SHA256 = `BF4B6899…B2ADE1` **逐字节完好**；`project/` 仅剩 `README.md`，无残留。

**引 `record.md` 对应行**：`[2026-10-09T14:48:43Z]` 的 `T1` · `T10` · `T5` · `T3` · `T6` · `还原复核` 六行（运行态记录**不随本仓分发**，故本附录将其**命令与读数**抄录如上，使结论**可复核**）。**D.6 的"实现侧口径"至此闭合**：`GAP-007` 的独立放行**已取得**。
