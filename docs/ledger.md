# 未竟事项 · 唯一台账（`docs/ledger.md`）

> **不在本台账里的"还没做"等于不存在**（出处：`AGENTS.md` §6）。
> 收纳 **`GAP-` / `INC-` / `DEFER-`** 三类；`ADR-` 落 `docs/adr/`，`MIG-` 落 `backend/migrations/`（当前无对应物）。
> 本仓为**自托管布局**（仓库 = 含 `.git` 的目录 = 工作区根），故本文件**在仓库内**、属 ✅ 入库。
> **本文件不引用仓库外文件**——凡作为证据的命令与输出，**原样抄录在本文件附录**，clone 的人可直接复核。

| 项 | 值 |
| --- | --- |
| 台账快照时间（UTC） | `2026-10-09T14:23:36Z` |
| 快照时 HEAD | `3b9030f`（全长 `3b9030ff76f8e56dc787658578b801795c6b6f72`） |
| 快照时入库文件数 | `16`（`git ls-files \| wc -l`） |
| 已用 `GAP-` 最大号 | `GAP-006` |
| 已用 `INC-` / `DEFER-` | 无（`0`） |
| 页名指针快照 | `.claude/progress-page.txt` → `project-progress.html`，字节 `112,…,108,10`，SHA256 `BF4B6899…B2ADE1` |

---

## 一、登记表

**状态取值**：`未解除` / `已解除` / `不适用（该环无对应物）` / `待人工裁定`。
**本表按编号升序，编号不复用、不重号。解除时改状态并加一行留痕，不删原条目。**

| 编号 | 缺口（一句话） | 证据（复跑命令见附录 B） | 解除条件 | 状态 |
| --- | --- | --- | --- | --- |
| **`GAP-001`** | `tools:` 名单里的工具名与**实际挂载名**不一致时**被静默丢弃**，**无报错**——通用风险；本案例已修，但**机制仍在** | 子代理自报工具清单 + `Get-Location; echo probe-ok` 回灌（附录 B.5）：清单 = `Read`/`Grep`/`Glob`/`PowerShell`，`probe-ok`，exit 0。而名单原写 `Bash` → 被丢弃 | 工具名由**实测**填入而非照抄；核验方法见附录 C.1。**须在每次新增/改动角色 `tools` 时执行** | `未解除`（机制性；方法已就位） |
| **`GAP-002`** | 进度页守卫**双静默**：`.claude/progress-page.txt` 一改错，「缺页静默」与「SHA 判据」**同时失效**（二者共用同一个 `$name` 与同一套路径推导）；**且「缺页静默」与「死代码」在观测上等价**（五种因果不可分） | 攻击 A（2026-10-09 实跑复现，**附录 D.1**）：把指针指向不存在的页名（页实为存在、含错 SHA）→ 守卫 **stdout 空、静默放行** | 让「指针**存在但读不出页名**」与「页**确实缺失**」**分别处置**；改后重跑附录 C.2 的两个用例 | **`已缓解`**（残余见下） |
| **`GAP-003`** | 守卫**误报**：页面写 **40 位完整 SHA** 时，与 **7 位短 SHA** 做**字符串全等**比对，被判为「落后」 | 攻击 B（2026-10-09 实跑复现，**附录 D.2**）：页面写 `<div>head <b>3b9030ff…6b6f72</b></div>` → 守卫 emit `decision:block`（**误报**：内容其实一致） | 改为**前缀比对**，改后重跑用例 | **`已解除`**（附录 D.3 实测） |
| **`GAP-004`** | **自托管布局下，`AGENTS.md` §5「入库策略」的"保障方式：位置，而非忽略规则"论证不成立**——框架文件已被 `git ls-files` 跟踪 | `git ls-files` 共 **16** 个文件，其中**含框架全部文件**（附录 B.2） | 人工裁定后同步改写 §5 表格与 §0.0 提示（二选一：**接受"本仓即框架"**，或**把仓库拆为子目录**） | **`已解除`**（**裁定：采纳"本仓即框架"**，附录 D.4） |
| **`GAP-005`** | **只读围栏修复后引入的新缝隙**：`falsifier` / `gate-auditor` 的执行改由**总控代跑**，但「**代跑是否真的发生**」**没有判据**——代跑缺失时，其产物会停在 `无法判定`，**与"确实没有 shell"外观相同** | 围栏修改本身（附录 B.5）；**无可跑命令能区分二者**——这正是指缝的性质 | 需要一个把「代跑」**投影到留痕**的机制（如：每次代跑强制在运行态记录里留一行，且该行可被机械核验） | `未解除` |
| **`GAP-006`** | 本工作区**尚无 CI / 合约 / 前端等对应物** → `AGENTS.md` §7 部分复核命令属**模板**、当前无对应物。**这不是缺口，而是"该环无对应物"**；按 §7 口径**登记备查** | `Test-Path .github` → `False`；`Test-Path Dockerfile` → `False`；`Test-Path docs` → `False`（登记本表之前） | **接回该环时解除**（届时 §7 对应行从"模板"转为"待实测"） | `不适用（该环无对应物）` |

### `GAP-002` 的残余（**已接受的代价**）

缓解后仍静默的一种情形：**指针指向一个不存在的页名**——它与"页确实缺失（尚未初始化）"
在观测上**不可分**，故**不报**。理由见 `AGENTS.md` §5「进度页同步」第 2 条与末条 ⚠️。
**缓解后的新行为**：指针文件**存在但读不出页名**（空 / 全空白 / 不可读）→ emit `systemMessage`。

### `GAP-003` / `GAP-004` 的解除留痕（2026-10-09）

两条的解除动作**都已落地**，实测见**附录 D.3 / D.4**。**D3 判据不得自审**：
改判据的是台账维护方（实现方），**放行仍须独立方跑负向用例**——故 `GAP-003` 的
「`已解除`」是**实现侧口径**，独立复核结果须**另派只读方**（`falsifier`）补记。
**不删原条目**：已发生的事实是**证据链**，不是待办事项（`AGENTS.md` §5「入库策略」连带纪律）。

---

## 二、附录 A · 登记前检索留痕（**撞车检查**）

`AGENTS.md` D4：**登记新编号前必须先全仓检索**——**撞车比漏登记更糟**。
以下为**首次登记前**在仓库内实跑的检索，命令与真实输出原样抄录。

```
$ git grep -n "GAP-"
AGENTS.md:149:- 标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）· `INC-`（线上故障）· `DEFER-`（延期债务）。
AGENTS.md:456:| `GAP-` | 质量缺口 | `"$REPO"/docs/`（唯一台账） | **任何"还没做"必须在此，否则它不存在** |
README.md:70:标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）·
prompts/全生命周期工程质量总监与系统架构师.md:16:   - 全局标识符严格定义：ADR-（架构决策）、MIG-（数据库迁移）、GAP-（质量缺口）、INC-（线上故障）、DEFER-（延期债务）。
prompts/全生命周期工程质量总监与系统架构师.md:30:- 07 排障：准出 = 故障复盘具备秒级时间线与对照实验 + 根因直接回写产品与架构文档 + 改进项全部转为 GAP-xx 台账。
exit=0
```

**5 处命中全部是"标识符定义/规则陈述"，无任何已用编号。**
同法检索 **`GAP-[0-9]`（带数字的具体编号）** → **零命中**（`exit=1`）。
> `exit=1` 是 `git grep` 的"零命中"约定，不是错误。故首次登记从 `GAP-001` 起，**不撞车**。

> ⚠️ **口径声明**：`git grep` **只搜已入库文件**，看不到未入库文件与被 `.gitignore` 掉的路径。
> 本次检索时本文件**尚未入库**，故**不在检索范围内**——不影响结论（它正是被登记的产物本身）。
> 若改用全盘 `Grep`，**零命中不等价于** `git grep` 的零命中——两种口径的差异**必须明说**。

---

## 三、附录 B · 证据抄录（**自包含，不依赖仓库外文件**）

### B.1 仓库根的解析（布局判据）

```
$ git rev-parse --show-toplevel
D:/MyDocuments/ai-collaboration-framework
exit=0
```

**仓库由含 `.git` 识别，名字任意**。本仓**工作区根自身含 `.git`** → **自托管布局**，
不存在 `project/` 子目录（`Test-Path project` → `False` 是**正常**，不是异常）。

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

其中 `AGENTS.md` / `CLAUDE.md` / `prompts/*` / `.claude/*` 正是 §5 表格里原标「❌ 不入仓库」的
**框架文件与运行态**；它们**确实在仓库里**。**补充实测**：`Test-Path .gitignore` → `False`
（本仓**无 `.gitignore`**，不存在"靠忽略规则挡住框架"的情形）。

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

子代理**自报**的工具清单 = `Read` / `Grep` / `Glob` / `PowerShell`
（本机 shell 挂载名为 **`PowerShell`**，**不是** `Bash`——`Bash` 在本机解析不了、被**静默丢弃**）。

只读角色的 `tools` 一行：

```
.claude/agents/falsifier.md     tools: Read, Grep, Glob     （原：…, Bash, PowerShell）
.claude/agents/gate-auditor.md  tools: Read, Grep, Glob     （原：…, Bash, PowerShell）
```

**为何去掉 shell**：`tools` 仅去掉 `Write`/`Edit` **挡不住写**——**shell 本身就是写后门**
（`Set-Content` / `Out-File` / `Remove-Item` 都能落盘、能删文件）。修法：**两个都去掉**。
**代价**：只读角色**跑不了命令**，其执行**交总控代跑**——这**正是 `GAP-005` 的来源**。

---

## 四、附录 C · 可复跑的核验命令

### C.1 `GAP-001` 的工具挂载核验（**改任何角色的 `tools` 后必跑**）

1. 派一个子代理，令其**自报可用工具的确切名字**；
2. 令其跑 `Get-Location; echo probe-ok`。
   **判据**：`probe-ok` 出现 **且** `LASTEXITCODE=0` → 该会话**确实有 shell**，
   且工具名以**自报清单**为准（本机实测为 `PowerShell`）。
   **名单是声明，挂载才是事实；两者不一致时无声。**

### C.2 进度页守卫的用例（**改页名后必跑**）

```powershell
# 用例① 缺页（页面不存在）-> 必须【静默 exit 0】（"尚未初始化"，放行是对的）
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例② 注入错误 SHA（页面【存在】）-> 必须 emit {"decision":"block"}
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例③ 指针文件存在但为空 -> 必须 emit {"systemMessage":…}   （GAP-002 缓解后的新分支）
# 用例④ 页面写 40 位完整 SHA（同一提交）-> 必须【静默】        （GAP-003 修复后的回归）
```

> ⚠️ **必须同时跑②与①**：只验「一致时静默」是**不够**的（D3）——它区分不了「正常」与「死代码」。
> 缺页分支与死代码**在观测上等价**（`GAP-002`），**只有 ② 仍有牙，才能反推 ① 的静默是"确无判据"。**
> 跑完**务必清理**临时页面，并复核指针文件字节未被改动（它由 Git 跟踪，`status --porcelain` 应干净）。

### C.3 本台账自身的登记规程

1. **先检索** `git grep -n "GAP-[0-9]"`，确认拟登记项未被既有编号覆盖；
2. **取号** = 本文件「已用 `GAP-` 最大号」+1，**不得复用、不得跳号**；
3. **写一条**：补齐「缺口 / 证据 / 解除条件 / 状态」四列；
4. **同步快照**：更新顶部「快照时间 / HEAD / 入库文件数 / 最大号」；
5. **改状态**：解除时改状态并**补一行留痕**，**不删原条目**。

---

## 五、附录 D · 守卫实测（**真实 stdout，2026-10-09 由台账维护方实跑**）

> **口径声明**：本节输出均为**本次实跑**所得，非转述、非推断。
> 但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**对守卫的独立放行；
> 独立复核仍须**另派只读方**（见 `GAP-002` 处置边界与 `GAP-003` 解除留痕）。

### D.1 攻击 A —— 指针指向不存在的页名（`GAP-002` 实证）

**前置**：进度页**存在**，状态条写错 SHA `0000000`（当时 HEAD 为 `3b9030f`）。

```
$ # 把 .claude/progress-page.txt 改为 'no-such-page.html'
$ powershell -NoProfile -ExecutionPolicy Bypass -File ".claude/hooks/check-progress.ps1"
（stdout 空）
guard exit=0

--- 对照：指针还原为真实页名 project-progress.html，同一页、同一错 SHA ---
{"decision":"block","reason":"进度页落后于仓库：project-progress.html 记录的 HEAD 是 0000000，而当前是 3b9030f。…"}
```

**读法**：同一页面、同一错 SHA，**只因指针里的页名不同**，一次**静默放行**、一次**正常阻断**
⇒ **指针文件是唯一开关**；指针一错，两个分支**同时失效**（`GAP-002` 成立）。

### D.2 攻击 B —— 页面写 40 位完整 SHA（`GAP-003` 实证，**修复前**）

```
$ Set-Content project-progress.html -Value "<div>head <b>3b9030ff76f8e56dc787658578b801795c6b6f72</b></div>"
$ powershell … -File ".claude/hooks/check-progress.ps1"
{"decision":"block","reason":"…记录的 HEAD 是 3b9030ff76f8e56dc787658578b801795c6b6f72，而当前是 3b9030f。…"}
```

**读法**：页面写的 SHA 与 HEAD **指的是同一个提交**，守卫却判「落后」⇒ **字符串全等是误报源**。

### D.3 修复后复跑（`GAP-003` 解除 / `GAP-002` 缓解的实证）

修复 `.claude/hooks/check-progress.ps1` 后，逐案复跑（页存在时皆用默认页名）：

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

**读法**：`CASE-6` 仍有牙 ⇒ `CASE-1/7/9` 的静默是**确无判据**，而不是"脚本死了"。
指针文件 **SHA256 与字节序列与攻击前逐字节一致**（无 BOM、无 CRLF）⇒ 未留残留。

> **一次真实险情（如实记录）**：首次复跑时测试脚本自身的 `WriteAllText` 重载**报错中断**，
> 导致指针文件**停在「空」状态**。已按台账快照的字节序列**逐字节还原**并复核 SHA256 与
> `git status`（如上）。**教训**：破坏性用例**必须先备份原值并保证清理路径不在崩溃点之后**——
> 否则"测试"本身就成了新的静默漂移源。

### D.4 `GAP-004` 解除了什么（**人工裁定：采纳"本仓即框架"**）

裁定后 `AGENTS.md` 的改写（§0.0 · §5 入库策略 · §5 推送前必做第 2 条 · §0.1）：

| 处 | 改前 | 改后 |
| --- | --- | --- |
| §0.0 | 「框架的**目标布局**是仓库为子目录…自托管布局下『框架在仓库之外』**不成立**」+ 独立的「仓库的识别方式」小节 | 一句话：**仓库 = 含 `.git` 的目录，名字任意；工作区根自身含 `.git` 即仓库本身**（自托管布局），`$REPO` 由 `git rev-parse --show-toplevel` 解析 |
| §5 入库策略 | 框架文件与运行态 = **❌ 不入仓库**；「**保障方式：位置，而非忽略规则**…结构上不可能」 | 两类 = **⬜ 按布局而定**；「**本仓即框架**…同在仓库内是**有意决定**」，两类布局差异收为**一句话** |
| §5 推送前第 2 条 | 「**框架文件围栏**…必须在推送范围内**不存在**」 | 「**推送范围的核对**…框架文件**在**范围内，这是有意决定；仍要核实而非假定」 |

**不拆仓库。** 残余影响（**须继续跟踪**，不随本条关闭）：
按 §5 判据，`record.md` / `memory.md` / 进度页等**运行态**在自托管布局下亦属入库；
它们是否**随仓库外发**由发布范围决定——`GAP-005` 与 §5 连带纪律仍指向此处。
