# 附录 D · 守卫实测（**真实 stdout**）

> 本文件是唯一台账 `docs/ledger.md` 的**取证附录 D**（体量拆分，见台账 §二）。**内容逐行未改**。
> **一处位置修正**：原 `### D.12` 错置于附录 A 之前，本次移回此处（D.11 与 D.13 之间）。


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

### D.8 `GAP-010` 的证据：运行态排除的来源，以及它随分发而变（2026-10-09T16:23Z 实跑）

**以下整段可在 clone 的检出里直接跑**（只读）。**采集时点**：本轮改动**尚未提交**，故 `git status` 显示 `?? .gitignore`——**提交后已复跑**，读数见 D.9。

```
$ git check-ignore -v memory.md record.md project-progress.html project
.gitignore:3:memory.md	memory.md
.gitignore:4:record.md	record.md
.gitignore:5:project-progress.html	project-progress.html
.git/info/exclude:15:project/	project
exit=0

$ git add -A --dry-run
add 'AGENTS.md'
add 'docs/ledger.md'
add '.gitignore'
exit=0

$ git status --porcelain
 M AGENTS.md
 M docs/ledger.md
?? .gitignore

$ git status --porcelain --ignored
 M AGENTS.md
 M docs/ledger.md
?? .gitignore
!! memory.md
!! project-progress.html
!! project/
!! record.md

$ git ls-files | wc -l
17            （本轮尚未提交；提交后含 .gitignore 应为 18——首次 `git ls-files` 的迟滞，非缺口）
```

**读法（三条，各自可独立复核）**：

1. **排除来源已分家**：三个运行态文件由 **`.gitignore:3/4/5`** 命中——**这个文件随仓库分发**，clone 的人拿到同一套规则；`project/` 由 **`.git/info/exclude:15`** 命中——**本机专属**，**刻意不随分发**（别人的 fork 里未必有 `project/`，写进 `.gitignore` 就是"指不到东西的引用"）。
2. **`--dry-run` 有牙**：它会把**将要提交**的东西逐条列出——`memory.md` / `record.md` / `project-progress.html` **一条都没有出现**，而 `AGENTS.md`（框架源）、`docs/ledger.md`（交付物）、`.gitignore`（框架文件）**都在**。即：**该排的被排掉，该进的照常进**。
3. **`--ignored` 是必需的第二只眼**：单看 `--dry-run` **分不清**"被规则排除"与"碰巧不存在"（后者同样不出现）。`--ignored` 把四个名字显式标成 `!!` ⇒ 它们是**存在且被排除**，不是"没有"。**只跑前者会把"文件根本不存在"读成"围栏有效"**——正是 `AGENTS.md` §8 那类判据夹缝。

### D.9 `GAP-010` 提交后复测 + `GAP-011` 的证据（2026-10-09T16:25:43Z 实跑）

```
$ git rev-parse --short HEAD
8537671                                   <- GAP-010 的改动已提交
$ git ls-files --error-unmatch .gitignore
.gitignore        exit=0                  <- .gitignore 确已被跟踪（不再是 ??）

$ git check-ignore -v memory.md record.md project-progress.html project
.gitignore:3:memory.md	memory.md
.gitignore:4:record.md	record.md
.gitignore:5:project-progress.html	project-progress.html
.git/info/exclude:15:project/	project

$ git add -A --dry-run
add 'README.md'
add 'docs/ledger.md'                      <- 只剩本轮两处；三个运行态一个都没出现

$ git status --porcelain --ignored
 M README.md
 M docs/ledger.md
!! memory.md
!! project-progress.html
!! project/
!! record.md

$ git grep -n "为什么把框架放在仓库之外"    # 改后：旧叙述的活性引用应为零
docs/ledger.md:30:…（本条目按「改前」原样引用，非活性叙述）
docs/ledger.md:48:…（同上，留痕行）
exit=0
（`README.md` **不再命中** ⇒ 该叙述已从 README 清除，台账内两处是**刻意保留的改前引用**，符合"不删原条目"）
```

**读法**：① `.gitignore` 已随仓库分发（`ls-files` 命中），三个运行态仍由它排除、`project/` 仍由本机 `info/exclude` 排除 ⇒ **分工在提交后依然成立**；② `--dry-run` 只剩本轮**该提交的两处**，说明**该进的在、该排的不在**；③ README 的旧叙述**已零活性命中**，D.9 同时充当 `GAP-011` 的解除证据。

### D.10 `GAP-009` 沙箱独立放行 + `:144`/`:164` 补齐（`2026-10-09T16:31:03Z` 实跑）

**口径**：**攻击由 `falsifier` 设计、命令由总控在 `%TEMP%` 沙箱代跑**（本仓不可证伪——`$ws` 恒有效 + `Select-Object -First 1` 使 `project/` 侧**连谓词都不求值**，故新旧判据在本仓**逐字节相同**）。**以下为台账维护方在本机复跑的同构实验**，读数一致。

```
sandbox = C:\Users\Yotoha\AppData\Local\Temp\gap009-83e4601d
GIT_DIR env = ''                                     <- 环境未设，故 GAP-013① 非本机实跑
2-commit repo at <ws>/project  short SHA = 2421fd8   <- 非空自证
CASE1  ws/.git = EMPTY DIR            exit=0  stdout={"decision":"block","reason":"进度页落后于仓库：sandbox-progress.html 记录的 HEAD 是 0000000，而当前是 2421fd8。…"}
CASE2  ws/.git = DANGLING GITFILE     exit=0  stdout={"decision":"block","reason":"…而当前是 2421fd8。…"}
cleanup: Test-Path sandbox = False
```

**真仓只读探针**（未写任何文件）：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空）  guard exit=0                          <- 页与 HEAD 一致 ⇒ 非净回归
ws             = D:\MyDocuments\ai-collaboration-framework
ws/.git exists = True
resolves to ws = .git                               <- 正序第一个候选即解析到工作区根
short HEAD     = 61f63de
```

**读法（三条）**：① 两例均 BLOCK，且 `reason` 里的"当前是"是**沙箱 `project/` 仓**的短 SHA ⇒ 证明守卫**真用了第二候选**，而旧码 `c0d828e` 在同一布局**静默**（反向对照「无 `.git`」旧码 **BLOCK** ⇒ 洞可达、旧码非死代码）；② 归因解剖：同一句 `rev-parse --git-dir`，作用域 `EAP='Continue'` → `NO-THROW`，**裸形式（继承 `Stop`）→ `THROWN`**——这正是 `:144` / `:164` 未设防的成因；③ 本轮按**同形**给 `:144` / `:164` 各套一层作用域 EAP（**只加 3 行，其余逻辑未动**，`:145` 的 `if (-not $head) { exit 0 }` 仍在原位）。**不得把本附录读成 `GAP-012` / `GAP-013` 已实测**——`GAP-012` 的覆盖实测见 **D.11**；`GAP-013` 在本机**环境未设**（`GIT_DIR=''`、`git` 在 PATH），属**读码推演**，状态**未解除**。

### D.11 `GAP-012` 的覆盖实测：unborn 仓致静默（`2026-10-09T16:31:03Z` 实跑，沙箱）

**为何另起一例**：D.10 的两例把 `ws/.git` 造成**无效**（空目录 / 悬空 gitfile），`rev-parse --git-dir` **失败** ⇒ 新谓词**正确地否决**该候选——那证明的是"**无效 `.git` 不被采纳**"，**不是** `GAP-012` 的输入（"`.git` **有效**但**无 HEAD**"）。故本节用**真 unborn 仓**（`git init` 后**零提交**）覆盖该格；`project/` 为两提交真仓（`d731b2c`）以保证旧码会锁到它。

```
sandbox = C:\Users\Yotoha\AppData\Local\Temp\gap012-1a5825d8
project/ real repo short SHA = d731b2c
ws is UNBORN repo?  git -C ws rev-parse --git-dir -> .git          <- 谓词所需：成功
ws HEAD (unborn)   rev-parse --short HEAD -> ''  exit=128          <- 但无 HEAD
CASE-U  ws = UNBORN repo (no commits), page SHA wrong   exit=0  stdout=[]

--- control: same ws now HAS 1 commit（加一次空提交，页面未动）---
CASE-C  ws = committed repo, same wrong page SHA        exit=0  stdout=[{"decision":"block","reason":"…记录的 HEAD 是 0000000，而当前是 4563627。…"}]
cleanup: Test-Path sandbox = False
```

**读法**：同一页面、同一错 SHA，**只因 `ws` 有没有 HEAD**，结果从**静默**翻转为 **BLOCK** ⇒ 该静默是**真 fail-open**（判据被绕过），**不是死代码**；`ws` 有提交时 `$ws` 被采纳且 `:144` 取到 HEAD，故 `project/` 侧连谓词都不求值——与 `GAP-012` 的推演一致。**本仓不可达**：本仓 `$ws` 恒为有 HEAD 的真仓（`61f63de`）。**触发前提**：有人在**工作区根**（而非 `project/`）`git init` 且**尚未提交**——与 `GAP-007` 是**同一族的"内层/外层仓混淆"**，只是这次的肇事者是工作区根自己。

### D.12 `GAP-012` / `GAP-013` 独立复核（`falsifier` 设计攻击 · 总控代跑；`2026-10-10T07:58:04Z`，沙箱）

**口径**：攻击清单由**只读方** `falsifier` 设计、命令由**总控代跑**（只读围栏下无 shell，见 `GAP-005`）——同 D.7，即 D3「判据不得自审」的落地。**以下读数由台账维护方在本机 `%TEMP%` 沙箱逐案复跑**，与代跑读数一致。**本仓进度页未被触碰**（探针读数见本节末）。

**A 组：`:144`（`GAP-012`）的 EAP 是否真有牙——`falsifier` 在 `catch {` 后插一行 stderr 标记后实测。**

```
A1 (带作用域 EAP)  unborn + 错 SHA  -> stderr 空                              exit=0
A2 (裸形式)        unborn + 错 SHA  -> stderr: CAUGHT:RemoteException         exit=0
A3 (带作用域 EAP)  同一 ws 补 1 提交 -> BLOCK（"当前是 823d76d"）             exit=0
A4 (裸形式)        同一 ws 补 1 提交 -> BLOCK（"当前是 823d76d"）             exit=0
   rev-list --count HEAD = 1   <- 自证已提交，非 unborn
```

**读法（三条）**：① **`:144` 的 EAP 是惰性的**——unborn 输入下**带** EAP **静默**（A1）、**裸**形式在同输入下 **`CAUGHT:RemoteException`**（A2），而**两者落点同形**（都到 `exit 0` 静默：裸形式抛→外层 `catch`；带 EAP→`$head` 空→下一行 `exit 0`）。**未插桩**复跑同结论：两形式均 **stdout 空 / exit=0**。② **A2 的抛出是故障引起的，不是结构性**——同一裸形式在**健康仓**上 A4 **BLOCK**（有 JSON）⇒ 该抛出只由 unborn 触发。③ **`:167` 不可证伪**：`:145` 成功 ⟹ HEAD 可解析 ⟹ `:167` 不会失败（除非两次 git 调用之间 HEAD 被改——TOCTOU，沙箱造不出稳定复现）⇒ **该处无法按其"同因"注释声称的方式被击穿**。

**B 组：`GAP-012` 的边界——断链 ref 不属此形态。**

```
B2c  refs/heads/master 写成 40 个 0（直接写 ref 文件）
     git rev-parse --short HEAD -> stdout "0000000"   exit=0     <- 仍【解析得出】
G1   同一输入 + 页写 1111111 -> BLOCK（"当前是 0000000"）
     V3  对照：ref 指向不存在的【非零】sha -> rev-parse "1111111" exit=0 也 BLOCK
```

**读法**：谓词的实际语义是「**能解析** HEAD」，**不是**「HEAD 指向真提交」——断链 ref 照旧解析、守卫照旧 BLOCK ⇒ `GAP-012` 的覆盖**仅真 unborn**。
> ⚠️ **复现陷阱（一行，实测踩过）**：`git update-ref refs/heads/<br> <40 个 0>` **会删除该 ref**（退化成 unborn），**造不出**断链——`rev-parse --short HEAD` 得 **空 / exit 128**。要造断链须**直接写 ref 文件**。误用会把 B2c 复现成 `GAP-012` 的那些读数。

**E 组：`GAP-013①`（`GIT_DIR`）的方向。**

```
E1  ws/.git = 空目录，无 GIT_DIR  -> (stdout 空) exit=0        <- 谓词【正确地】否决该候选
E2  同一空 .git，GIT_DIR = 真仓   -> BLOCK（"当前是 0b6c54c"）  <- 0b6c54c 是【另一个仓】的 HEAD
```

**读法**：中和的形态下**下游是 BLOCK（可见）**，不是静默——谓词**恰好**不再否决本应被否决的候选；`reason` 里的"当前是"是**另一个仓**的 HEAD ⇒ `GIT_DIR` **劫持 `rev-parse`** 这一机制**被直接观测到**。**严重度低于 ②**：判错但**看得见**。在本仓**非主要效应**——`$ws` 本就先中，`:138` 子句早被 `Test-Path` 短路。

**F 组：`GAP-013②`（`git` 不在 `PATH`）——两向 + 归因。**

```
F1  正常 PATH                  -> BLOCK（有 JSON）                     exit=0
F2  剥 PATH                    -> stdout 空、【stderr 也空】           exit=0
    F2a 同环境探针             -> git: CommandNotFoundException（powershell 仍解析）
F3  剥 PATH + 插桩副本         -> 【stderr】CAUGHT:CommandNotFoundException
```

**读法（两条）**：① **归因成立**——异常抛在 `Where-Object` 的谓词里、冒到外层 `catch { exit 0 }` ⇒ 静默，且**连 stderr 都没有**（F2 与 F3 的唯一差别就是那行插桩）；② **关键机制**：作用域 `EAP='Continue'` **关不掉这条**——它只约束「原生命令写 stderr 的非零退出」，**不管「命令找不到」**（后者是 `CommandNotFoundException`，与 `GAP-008` 的失败面**不同**，尽管症状同形）。

**G5 组：`CLAUDE_PROJECT_DIR` 猜测——已推翻。**

```
G5-A  .claude/settings.json:8 的调用行，变量为空 -> powershell.exe 报错：
      "The argument '/.claude/hooks/check-progress.ps1' to the -File parameter does not exist."
      exit = -196608（两次复跑一致；非 0）
G5-B  同一行、变量解析为真实路径（对照）-> guard 正常运行，stdout 空，exit = 0
```

**读法**：缺该变量时是**可见失败**（非零退出 + 明确报错），**不构成"与 ② 同族的静默通道"** ⇒ `falsifier` 的猜测被实测推翻，**不登记为新缺口、不占号**。
> **口径（一句）**：`CLAUDE_PROJECT_DIR` 在本机 shell **本就未设**（`$env:CLAUDE_PROJECT_DIR` 读数为空），而 `G5-B` 用的是**路径替换后的命令**、非变量注入，故本组的对照是「**空替换 vs 真路径替换**」；**未验证** harness 注入该变量时的行为。

**本仓只读探针 + 清理复核**（无残留）：

```
guard stdout = []  exit=0            <- 页与 HEAD 一致 ⇒ 非净回归
ws = D:\MyDocuments\ai-collaboration-framework     short HEAD = 9ce688b
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10 一致）
leftover d12* sandbox dirs = 0
```

**放行结论（本轮的收口，一句话）**：第一类（`:144` 的 EAP）**不能按"关上了失败通道"放行**——判为**防御性同形、未证明有牙**，**保留**但**理由已改正**（见 `:144` 注释）。**本节各组的执行者即台账维护方**（代跑），按 D3 **不构成**对 `falsifier` 的独立放行替代——**攻击由 `falsifier` 设计**这一点满足"设计者 ≠ 写守卫者"，但**放行的最终签署仍应由只读方给出**。

### D.13 `GAP-013②` 修复实测（**实现侧口径 · 放行待 `falsifier`**；`2026-10-10T08:27:58Z` 实跑）

**口径（一句）**：本节输出均为**本次实跑**所得，非转述、非推断；但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**独立放行，独立复核须**另派只读方**（`falsifier`）补记。

**① 语法解析 + 行尾完整性（LF 必须保住）**：

```
$ [System.Management.Automation.Language.Parser]::ParseFile(<hook>, [ref]$tokens, [ref]$errors)
ParseErrors=0
first4=35,32,83,116   （= '#',' ','S','t'，无 BOM）
CRLF=0 bareLF=198     （改前 bareLF=185 ⇒ 纯 LF，未被编辑器写成 CRLF）
```

**② 本仓只读探针（页与 HEAD 一致 ⇒ 非净回归；未写任何文件）**：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空） exit=0                      <- 页记录 d867d60，HEAD 亦 d867d60
```

**③ 负向：注入错 SHA ⇒ 必须仍有牙（证明加了前置检查后判据未削弱）**。同一页面，`finally` 内**逐字节还原**：

```
CASE-NEG(sandbox)  真仓 .git 副本 + 页写 0000000 -> exit=0
    stdout={"decision":"block","reason":"进度页落后于仓库：sandbox-progress.html 记录的 HEAD 是 0000000，而当前是 d867d60。…"}
CASE-NEG(repo)     本仓页注入 0000000            -> exit=0
    stdout={"decision":"block","reason":"进度页落后于仓库：project-progress.html 记录的 HEAD 是 0000000，而当前是 d867d60。…"}
page SHA256 before=39E198F5…28C48E6
page SHA256 after =39E198F5…28C48E6   restored=True
```

**④ 本次修复点：剥掉 `git` 的 `PATH`（保留 `System32\WindowsPowerShell\v1.0`）**。

**注入自证**（`Get-Command` 布尔值，剥前 / 剥后）：

```
psDir = C:\WINDOWS\System32\WindowsPowerShell\v1.0
stripped PATH = C:\WINDOWS\System32\WindowsPowerShell\v1.0;C:\WINDOWS\System32;C:\WINDOWS
stripped PATH contains 'Git'? False
A 子进程 正常 PATH      -> git=True  powershell=True
B 子进程 剥 git 的 PATH -> git=False powershell=True     <- 注入有效，且探针仍能起来
```

**两向对照（同一沙箱、同一页、同一错 SHA，四格全跑）**：修复前守卫 = **HEAD 提交的 blob 逐字节重建**（校验 `RECONSTRUCTION == committed HEAD blob` → `True`），非"凭记忆重写"。

```
SANDBOX=<%TEMP%\gap013b-…>   sandboxHEAD=d867d60   page records 0000000（页面是错的）
F1 【修复前】+ 正常 PATH      -> exit=0  BLOCK（"…而当前是 d867d60。"）   <- 对照：判据本来有牙
F2 【修复前】+ 剥 git 的 PATH -> exit=0  stdout=[]  stderr=[]            <- 缺陷本尊：静默、零提示
F3 【修复后】+ 剥 git 的 PATH -> exit=0
   stdout={"systemMessage":"进度页守卫无法运行：PATH 上找不到 git。守卫需要 git 读取仓库 HEAD；缺它时将无法判断进度页是否落后。请把 git 加入 PATH，或确认本机已安装 git。"}
F4 【修复后】+ 正常 PATH      -> exit=0  BLOCK（"…而当前是 d867d60。"）   <- 有牙，未被前置检查削弱
```

**读法（三条）**：① `F1` 与 `F2` **同页同 SHA、只差 `PATH`** ⇒ 那个静默**确由缺 `git` 引起**（`F2` 的 `stderr` 也是空的，与它正常时的静默**在观测上不可分**——这正是 `GAP-013②` 的性质）；② `F3` 由**静默**变为**可见的 `systemMessage`** ⇒ 本修复**关上了这条静默通道**，且**刻意不是 `decision:block`**（缺 `git` 时**无法判定**落后，逐轮阻断会让框架不可用）；③ `F4` **仍 BLOCK** ⇒ 前置检查**没有**削弱原有判据（`AGENTS.md` §5 「用例② 仍有牙」的口径）。

**清理与完整性复核（无残留）**：

```
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10/D.12 一致）
page    SHA256 = 39E198F5939AC4831352EAB3BB41E1851A23E3DDECD5960D0C77C444728C48E6   （探针前后一致）
$ git status --porcelain
 M .claude/hooks/check-progress.ps1
$ git status --porcelain --ignored
 M .claude/hooks/check-progress.ps1
!! memory.md
!! project-progress.html
!! project/
!! record.md
!! 我要做什么.txt
leftover gap013b* sandbox dirs = 0
```

**读法**：指针**逐字节未被触碰**（SHA256 与历次一致）；工作树**只有守卫一处改动**（台账本轮改动在本节采集之后），**未新增/删除任何入库文件** ⇒ 无测试残留。
> ⚠️ **两条实测踩过的坑（供复跑者）**：① **剥 `PATH` 必须保留 `System32\WindowsPowerShell\v1.0`**——否则外层探针自己起不来，会把"探针失败"读成"守卫行为"；② **`Set-Content` / `Out-File` 在本机 PS 5.1 下既加 BOM 又把行尾写成 CRLF**（实测同一内容：`WriteAllText` → `97,10,98,10`；`Set-Content -Encoding utf8` → `239,187,191,97,10,98,13,10`；`Out-File -Encoding utf8` **同**）⇒ 改此类文件一律用 `[System.IO.File]::WriteAllText` + `New-Object System.Text.UTF8Encoding($false)`，否则 `*.ps1 text eol=lf` 的归一被绕过、**行尾与 BOM 都成为测量口径的变量**（与 `AGENTS.md` §8「覆盖率口径」同源）。

### D.14 `GAP-013②` / `GAP-002` 通道与谓词复修实测（**实现侧口径 · 放行待 `falsifier`**；`2026-10-10T08:50:02Z` 实跑）

**口径（一句）**：本节输出均为**本次实跑**所得，非转述、非推断；但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**独立放行，独立复核须**另派只读方**（`falsifier`）补记。**沙箱**：`%TEMP%\gap013c-*`，内含守卫副本 + **真仓 `.git` 副本**（`short HEAD = d867d60`）+ 页 `sandbox-progress.html`（写 `0000000`，即**错 SHA**）+ 指针。

**① 语法解析 + 行尾完整性（LF 必须保住）**：

```
$ [System.Management.Automation.Language.Parser]::ParseFile(<hook>, [ref]$tokens, [ref]$errors)
ParseErrors=0
hook bytes=11440  first4=35,32,83,116   （= '#',' ','S','t'，无 BOM）
bareLF=197  CR=0                         （改前 bareLF=198 ⇒ 仍纯 LF，未被编辑器写成 CRLF）
自指行号残留（`:\d{2,3}` 命中数）= 0     （D1 漂移已修：两处改为描述式指代）
```

**② 四格主用例（同一沙箱、同一页、同一错 SHA）**：

```
POS  正常 PATH，页与 HEAD 一致       -> exit=0  stdout=[]  stderr=[]
NEG  正常 PATH，页 SHA 错             -> exit=0  stdout=[{"decision":"block","reason":"进度页落后于仓库：sandbox-progress.html 记录的 HEAD 是 0000000，而当前是 d867d60。…"}]  stderr=[]
FIX  剥 git 的 PATH，同页同错 SHA     -> exit=1  stdout=[]  stderr=[进度页守卫未运行：PATH 上的 git 不可用（缺失或无法执行）。本轮未检查进度页是否落后。]
PTR  正常 PATH，指针写全空白          -> exit=1  stdout=[]  stderr=[进度页指针异常：.claude/progress-page.txt 存在但读不出页名（空 / 全空白 / 不可读）。守卫已回退到默认页名，可能在看一个错误的文件。]
```

**③ `FIX` 格的注入自证**（剥 `PATH` 前后，`Get-Command` 布尔值）：

```
stripped PATH = C:\WINDOWS\System32\WindowsPowerShell\v1.0;C:\WINDOWS\System32;C:\WINDOWS
stripped PATH contains 'Git'? False
PROBE 正常 PATH      -> git=True   powershell=True
PROBE 剥 git 的 PATH -> git=False  powershell=True     <- 注入有效，且探针仍能起来
```

**④ `A1` 复现格——`falsifier` 击穿的正是这一格（0 字节 `git.exe` 前置在 `PATH`）**：

```
fakegit\git.exe = 0 bytes，置于 PATH 首位
探针（A1 环境）：
  Get-Command git -> True   source=…\fakegit\git.exe   bytes=0    <- 旧谓词【确实被骗过】，自证成立
  functional probe -> bool=False  (THREW:ApplicationFailedException)  <- 新谓词识别出"跑不了"

A1-before  旧守卫 + 0 字节 git.exe + 错 SHA  -> exit=0  stdout=[]  stderr=[]      <- 缺陷本尊：静默、零提示
A1-after   本轮守卫 + 同环境同页同错 SHA      -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 不可用（缺失或无法执行）。本轮未检查进度页是否落后。]
```

> ⚠️ **`A1-before` 的对照侧是哪一份（必须明说，不得含糊）**：它取自 **`git show HEAD:.claude/hooks/check-progress.ps1` 的 blob**（`10667` 字节；该 blob 是 `d867d60` 提交的版本，**早于** `2026-10-10T08:27:58Z` 那次未提交的 13 行插入）。故它**不是**"08:27 版守卫"，而是**含 `Get-Command git` 检查的更早版本**——但**这不削弱该格**：① 本轮 `A1` 击穿的是**同一句 `Get-Command git`**（`git diff` 实测该句**未被触及**，仅其判据被换掉），两版在该环境下的行为**同形**；② 严格按"同一谓词"论，**08:27 版守卫已被本轮编辑覆盖、不再留存**（未提交、无副本）⇒ **该格无法用 08:27 版复跑**，此点**如实标注**，不冒充。

**⑤ 本仓只读探针 + 清理复核（无残留）**：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空）  guard exit=0                       <- 页与 HEAD 一致 ⇒ 非净回归
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10/D.12/D.13 一致）
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
page    SHA256 = 39E198F5939AC4831352EAB3BB41E1851A23E3DDECD5960D0C77C444728C48E6   （探针前后一致）
leftover gap013c* / gap013c2* sandbox dirs = 0
$ git status --porcelain
 M .claude/hooks/check-progress.ps1
 M docs/ledger.md
```

**读法（三条）**：① **`A1-before` 与 `A1-after` 同环境、同页、同错 SHA，只差守卫版本** ⇒ 那个静默**确由旧谓词只证"可解析"引起**，新谓词**关上了这条静默通道**；② **`NEG` 仍 `decision:block`** ⇒ 换谓词与换通道**没有削弱原有判据**（`AGENTS.md` §5「用例② 仍有牙」的口径），故 `POS` 的静默可读作"确无判据"；③ **`FIX` / `PTR` 均为 `exit 1` + stderr**（**不是 0、不是 2、不是 `systemMessage`**）⇒ 两个提示分支**同形**，D4 的"两处不同成熟度"未产生。**残余（须继续跟踪，不随本节关闭）**：`exit 1` 是**非阻断错误**，**仍不阻断本轮结束**——与 `AGENTS.md` §5「提醒会被忽略，阻断不会」的张力**已按人工裁定接受**，故状态是 `已缓解（残余）`。
> ⚠️ **两条实测踩过的坑（本节新增，供复跑者）**：① **探针不要用 `powershell -Command "…"` 传内联脚本**——外层 PS 会先剥一层引号，`2>$null` 被吃掉后 `git` 的 stderr 直接冒到子进程 stderr，**把"探针返回空"误读成"探针没生效"**；本节改用 `-File` + 独立 `.ps1`（写文件仍走 `WriteAllText` + 无 BOM UTF-8）。② **`A1-before` 的对照侧必须取自 `git show HEAD:…` 的 blob**，不能用"我记得改前是什么样"——否则对照格本身就成了新的漂移源（与 D.3/D.6 两次清理险情同源）。

### D.15 `GAP-015` 结构性修复实测（**实现侧口径 · 放行待 `falsifier`**；`2026-10-10T09:40:11Z` 实跑）

**口径（一句）**：本节输出均为**本次实跑**所得，非转述、非推断；但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**独立放行，独立复核须**另派只读方**（`falsifier`）补记。**沙箱**：`%TEMP%\gap015f-*`（本轮守卫）+ `gap015fB-*`（`e2b4a2e` 版守卫）+ `gap015f0-*`（`d867d60` 版守卫），**各含真仓 `.git` 副本**（`short HEAD = e2b4a2e`）+ 页 `sandbox-progress.html`（写 `0000000`，即**错 SHA**）+ 指针。**沙箱页的 SHA 是刻意写错的**：判据只在"页面落后"时有牙，写对就只能观测到静默。

**① 语法解析 + 字节完整性（LF / 无 BOM 必须保住）**：

```
$ [System.Management.Automation.Language.Parser]::ParseFile(<hook>, [ref]$tokens, [ref]$errors)
ParseErrors = 0
bytes=15657  first4=35,32,83,116   （= '#',' ','S','t'，无 BOM）  CR=0  LF=264
自指行号残留（`:\d{2,3}` 命中数）= 0        （改为描述式指代；上轮硬编码 :138/:169 因插入行整体漂移，本轮清零）
Invoke-GitChecked 调用点 = 8                （helper 定义 1 + 调用 7）
裸 git 调用（helper 之外）= 0               （全部 git 调用已收拢，退出码只在 helper 内读）
'2>$null' 计数 = 5                          （保留原 stderr 抑制：守卫静默时**不得**往 stderr 漏 git 原始输出）
```

**② 三份守卫的身份自证（评分前先证"跑的是哪一份"）**：

```
NEW  bytes=15657  sha256=77C9074A03900E37A5FD8927D116140D31445469391FC88360D2372C123DE9E5   == 本仓工作树: True
OLD  bytes=11440  sha256=DE956E4B3E2EFC3CC33CAEE0F8C555D6170F2EB0464D0FEB6942771FE40AACBF   == e2b4a2e blob: True
OLD0 bytes=10668  sha256=5F47294A320C7F8D71DF4A4729EA429EAEC8A488C5A34EC28E5C2B9A95EC1B1D
blob 身份核对: git rev-parse e2b4a2e:.claude/hooks/check-progress.ps1 = 92a698794292e6d76ce7b165f1a8538894b6fe06
              git rev-parse d867d60:.claude/hooks/check-progress.ps1 = c93624a66b21af4cbc1d9f3b712a315251ec87fa
两个 OLD 均由 `git show <rev>:<path>` 逐字节导出（cmd 重定向），非"凭记忆重写"
e2b4a2e blob 含 `[Console]::OutputEncoding` 行？ True（1 处）   d867d60 blob ？ True（2 处）   NEW ？ True
```

> ⚠️ **一个必须点出的改前事实（否则 `A1` 那格会被误读成"回归"）**：**`e2b4a2e` 版守卫已经不再用 `Get-Command`**（该版是上轮把谓词换成"功能探针"的结果）——故 **`A1` 在 `e2b4a2e` 上已不可复现**，本轮 `A1` 的**缺陷侧对照**取的是**更早的 `d867d60` 版**（那一版确实用 `Get-Command git`）。`V13` 则**两版都可复现**（`e2b4a2e` 与 `d867d60` 皆静默），因为它的根因在**下游的字符串比较**，与谓词无关。

**③ 注入自证（每一格先证"注入确实生效"，再判分）**：

```
NORMAL    Get-Command git=True  source=D:\Git\mingw64\bin\git.exe
          git --version out=[git version 2.49.0.windows.1] exit=0  threw=no  powershell=True
STRIPPED  Get-Command git=False source=-        （stripped PATH = C:\WINDOWS\System32\WindowsPowerShell\v1.0;C:\WINDOWS\System32;C:\WINDOWS）
          git --version threw=CommandNotFoundException  powershell=True     ← 剥 git 但保留 powershell，探针仍能起来
A1        Get-Command git=True  source=…\fakegit\git.exe   （该文件 0 字节）
          git --version out=[] exit=0  threw=ApplicationFailedException      ← 旧谓词【确实被骗过】，自证成立
V13       Get-Command git=True  source=…\shim\git.cmd
          git --version out=[git version 9.9.9] exit=128
          git -C <sandbox> rev-parse --short HEAD out=[git version 9.9.9] exit=128   ← 输出相同、退出码同为 128
A4c       Get-Command git=True  source=…\emptygit\git.cmd
          git --version out=[] exit=0  threw=no                             ← 输出为空但【退出码 0】= 可用
```

**④ 主用例矩阵（同一沙箱、同一页、同一错 SHA；每格标注跑的是哪一份守卫）**：

```
POS-new   页与 HEAD 一致（正确页）     -> exit=0  stdout=[]  stderr=[]                         静默 ✔（真·正向）
POS-old   同上（e2b4a2e）              -> exit=0  stdout=[]  stderr=[]                         静默 ✔（对照）
NEG-new   页 SHA 错                    -> exit=0  stdout=[{"decision":"block",…"而当前是 e2b4a2e"…}]   有牙 ✔
NEG-old   同上（e2b4a2e）              -> exit=0  stdout=[{"decision":"block",…}]               有牙 ✔（判据未被削弱）
FIX-new   剥 git 的 PATH               -> exit=1  stdout=[]  stderr=[进度页守卫未运行：…]       可见 ✔
FIX-old   同上（e2b4a2e）              -> exit=1  stdout=[]  stderr=[进度页守卫未运行：…]       同上（两分支同形）
A1-new    0 字节 git.exe 在 PATH 首位  -> exit=1  stderr=[进度页守卫未运行：…]                 GAP-015① 已关 ✔
A1-old    同上（e2b4a2e）              -> exit=1  stderr=[进度页守卫未运行：…]                 同上（该版已不靠 Get-Command）
A1-old0   同上（d867d60）              -> exit=0  stdout=[]  stderr=[]                          ← 缺陷本尊：静默、零提示
V13-new   恒 128 + 常量 shim 在首位    -> exit=1  stderr=[进度页守卫未运行：…]                 GAP-015③ 已关 ✔
V13-old   同上（e2b4a2e）              -> exit=0  stdout=[]  stderr=[]                          ← 缺陷本尊：静默、零提示
V13-old0  同上（d867d60）              -> exit=0  stdout=[]  stderr=[]                          ← 同一静默
A4c-new   空输出 exit-0 shim 在首位    -> exit=0  stdout=[]  stderr=[]                         正确：判为可用，不再误报 ✔
A4c-old   同上（e2b4a2e）              -> exit=1  stderr=[进度页守卫未运行：…]                 ← 缺陷本尊：**误报**（每轮提示）
PTR-new   指针写全空白                 -> exit=1  stderr=[进度页指针异常：…]                    与 FIX 同形 ✔
```

**读法（四条）**：① `A1-old0` / `V13-old0` **同环境、同页、同错 SHA，只差守卫版本**，二者皆 **`exit=0` 且 stderr 为空** ⇒ 那两个静默**确由"用输出真值/字符串当判据"引起**（与它正常时的静默**在观测上不可分**，这正是 `GAP-015` 的性质）；修复后同格变为 **`exit=1` + stderr** ⇒ 通道**由静默改为可见**。② `A4c` 是**反方向**的失败——不是静默而是**每轮误报**（`e2b4a2e` 的 `exit=1`），修复后 `exit=0` ⇒ **取真值**与**取退出码**的差别在两向上都可观测。③ **`NEG` 仍 `decision:block`、`POS` 仍静默** ⇒ 换判据**没有削弱原有判据**（`AGENTS.md` §5「用例② 仍有牙」的口径），故 `POS` 的静默可读作"确无判据"。④ `FIX` / `PTR` **均为 `exit 1` + stderr**（不是 0、不是 2、不是 `systemMessage`）⇒ 两个提示分支**同形**，D4 的"两处不同成熟度"未产生。

**⑤ 残余实测（`GAP-015` 标「已缓解」而非「已解除」的**直接依据**）**——**恒 `exit 0` 且输出恒定的 shim**：

```
CONST  shim: @echo off / echo deadbeef…(40 hex) / exit /b 0
  git --version              out=[deadbeef…]  exit=0
  rev-parse --git-dir        out=[deadbeef…]  exit=0
  rev-parse --short HEAD     out=[deadbeef…]  exit=0
  rev-parse --verify 0000000^{commit} out=[deadbeef…]  exit=0     ← 与 HEAD 输出【完全相同】
CONST-new  守卫 -> exit=0  stdout=[]  stderr=[]                    ← **仍静默**
```

**读法**：该 shim **伪造的正是退出码本身**，故"以退出码为唯一判据"这条规则**在规则内不可消**——判据与攻击面同源。**触发前提**：`PATH` 上已存在一个**恶意或损坏**的 git；与 `GAP-013①`（`GIT_DIR` 劫持 `rev-parse`）**同族：环境使判据失效**。**严重度如实标注**：**不高于** `GAP-013①`——二者都要求先污染守卫的运行环境，**不是"页面落后却不拦"的常规路径**。

**⑥ `chcp` 码页格 + **机制探针**（**上一轮的对照格其实没区分开，故本轮改测机制**）**：

```
机制探针（同一句 [Console]::Error.WriteLine("进度页")）：
  plain-normal  OE=gb2312  stderr-hex= BD F8 B6 C8 D2 B3 0D 0A        ← GBK
  plain-cp936   OE=gb2312  stderr-hex= BD F8 B6 C8 D2 B3 0D 0A        ← GBK
  utf8-normal   OE=utf-8   stderr-hex= E8 BF 9B E5 BA A6 E9 A1 B5 0D 0A ← UTF-8
  utf8-cp936    OE=utf-8   stderr-hex= E8 BF 9B E5 BA A6 E9 A1 B5 0D 0A ← UTF-8
  （cp437 对照组：`OE=IBM437` / `OE=Windows-1252` 亦经探针自证，见下方"码页注入自证"）

码页注入自证（cmd /c "chcp N >nul & powershell …" —— 码页在【同一控制台、powershell 启动前】设好）：
  cp-default  chcp-output=437   OutputEncoding=utf-8
  cp-936      chcp-output=936   OutputEncoding=gb2312
  cp-437      chcp-output=437   OutputEncoding=IBM437
  cp-1252     chcp-output=1252  OutputEncoding=Windows-1252

守卫本体：
  CP936-FIX-new  剥 git 的 PATH，chcp 936 -> exit=1  stderr-hex=E8 BF 9B …  （UTF-8，中文可读）✔
  CP936-FIX-old  同上（e2b4a2e）          -> exit=1  stderr-hex=BD F8 B6 C8 D2 B3 … （**GBK 乱码**）← 缺陷本尊
  CP437-FIX-new  剥 git 的 PATH，chcp 437 -> exit=1  stderr-hex=E8 BF 9B …  （UTF-8）✔
  CP437-FIX-old  同上（e2b4a2e）          -> exit=1  stderr-hex=3F 3F 3F 3F … （**全问号**）← 缺陷本尊
  CP936-NEG-new  错 SHA，chcp 936         -> exit=0  stdout=[{"decision":"block",…}]   ✔
  CP936-NEG-old  同上（e2b4a2e）          -> exit=0  stdout=[{"decision":"block",…}]   ✔
```

**读法（三条）**：① **`A.1.3` 的 (a)(b) 两问均得正**：(a) `chcp 936` 下 `exit 1` 分支的 stderr 中文**可读**（UTF-8 字节 `E8 BF 9B…`，**不是** GBK 乱码、**不是**问号）；(b) `chcp 936` 下注入错 SHA **仍然 `decision:block`** ⇒ 恢复编码行**没有**把 block 路弄死。② **编码行是"删了就静默变形"的那类改动**——同一句 `WriteLine`，**带**该行 → UTF-8（任何码页下一致）；**不带** → 随码页变形（936 → GBK；437 → 全问号）。**注意区分两种失败**：GBK 是"**可见但看不懂**"，全问号是"**可见但信息全丢**"——**都不是静默**，故这条**不属"静默通道"**，而是**可读性回归**。③ **上一轮"未击穿"结论的口径已查明**：该轮用 `Start-Process … -Command "chcp 936; …"`，而**码页未在 `powershell` 启动前于同一控制台设好**（本轮 `cp-default` 实测本机默认 `437`，而上一轮却读到 `65001`）⇒ **对照格无效**，故本节**改测机制**（探针 + 自证），**不以"上一轮没击穿"为据**。**本机默认码页实测 = `437`，`OutputEncoding = utf-8`**（`cp-default` 格）。

**⑦ `GAP-012` 回归（未改动的既有边界，须证明未被本轮修复破坏）**：

```
UB .git=True   git -C UB rev-parse --git-dir    out=[.git] exit=0     ← 谓词通过（.git 能解析）
               git -C UB rev-parse --short HEAD out=[] exit=128       ← 但无 HEAD
UNBORN-new     ws = unborn 仓 + 页写错 SHA       -> exit=0  stdout=[]  stderr=[]   ← 与改前同形（GAP-012 未变）
control        同一 ws 补 1 次提交（count=1, HEAD=b4a4204）-> exit=0  stdout=[{"decision":"block",…"而当前是 b4a4204"…}]
```

**读法**：同一页、同一错 SHA，**只因 `ws` 有没有 HEAD**，结果从**静默**翻转为 **BLOCK** ⇒ 该静默是**真 fail-open**（判据被绕过），**不是死代码**；且**与改前同形** ⇒ 本轮结构性修复**未改变** `GAP-012` 的行为（`if (-not $head) { exit 0 }` 仍在原位）。**注意**：`UNBORN-new` 的 `stderr` 为**空**（不是 `fatal: Needed a single revision`）——因为 `rev-parse` 的 `2>$null` **被保留**；这正是本轮**刻意不做**的那一处扩张（见下方第 ⑨ 条）。

**⑧ 本仓只读探针 + 清理复核（无残留）**：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空）  stderr 空  guard exit=0                       <- 页与 HEAD 一致 ⇒ 非净回归
repo hook sha256 = 77C9074A03900E37A5FD8927D116140D31445469391FC88360D2372C123DE9E5
pointer sha256   = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10/D.12/D.13/D.14 一致）
pointer bytes    = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
page    sha256   = FCF35FA8D66F665EBD9F43078D8B9F2C121D3FE9EDB41BC0D653AF5CBF9D8362   （探针前后一致）
$ git status --porcelain
 M .claude/hooks/check-progress.ps1
```

**读法**：指针**逐字节未被触碰**；本仓进度页**未被注入**（本轮全部破坏性用例都在 `%TEMP%` 沙箱、各持 `.git` 副本，**未改本仓页**）⇒ 无残留。

**⑨ 本轮**刻意没做**的一处（如实标注，勿读成遗漏）**：沙箱里为读取 git 原始 stderr 曾**临时去掉** `2>$null`，该试验暴露出**多出一处行为变化**——unborn 格会把 `fatal: Needed a single revision` **漏到 hook 的 stderr**（在正常仓上该 stderr 由 Stop hook 记入转录）。按"**不顺手扩大改动范围**"的要求，**已把五处 `2>$null` 逐处恢复**（实测 `'2>$null' 计数 = 5`），**最终守卫的行为与改前逐格一致**（见第 ⑦ 条）。**该扩张未落地、不登记为缺口**，仅留痕以免复跑者以为漏了。

**⑩ 守卫头部注释里那三条"静默通道"的说法，逐条都有实测格支撑（不得读成修辞）**：注释写的三句与实测格一一对应——① "`Get-Command git` 只证**名字可解析**" → `A1-old0`（`d867d60` + 0 字节 `git.exe`）**静默 `exit=0`**；② "取**输出真值**而非退出码 → 一个**打印为空但 `exit 0`** 的 git 被判成不可用（**误报**）" → `A4c-old`（`e2b4a2e`）**`exit=1`**；③ "把两个 `rev-parse` 的**输出当字符串比** → 恒 `exit 128` 的 shim 使两边同为垃圾 → 判'一致'" → `V13-old0` **静默 `exit=0`**。**三条都有格、格格有自证**，故注释里的说法**不是推断**（D1）。

> ⚠️ **两条实测踩过的坑（本节新增，供复跑者）**：① **`$LASTEXITCODE` 的作用域结论不能照抄**——本机 `Windows PowerShell 5.1.19041.6456` 实测：`& { … }` 子作用域里跑的 git，其 `$LASTEXITCODE` **在父作用域可读**（P1–P3：`7`/`9`/`11` 均穿透父作用域；P7 dot-source 亦穿透；P8 在 `Where-Object` 内亦穿透），**但**该值经**未限定赋值**会落进子作用域而丢失 ⇒ helper 内必须**显式** `$script:__gitExit = $LASTEXITCODE`（P4 对照）。**故形式按实测选，不按惯例猜。** ② **测码页必须用 `cmd /c "chcp N >nul & powershell …"`**，**不能**用 `powershell -Command "chcp N; …"`——后者码页**在 powershell 启动后才设**，而 `[Console]::OutputEncoding` **在启动时已定**，于是"注入"看着生效、实际无效（本轮 `cp-*` 自证格就是为此设的）。

### D.16 `GAP-015` 负向金丝雀实测（**`falsifier` 设计 · 总控代跑**；`2026-10-10T10:05:21Z` 实跑）

**口径（一句）**：**金丝雀由只读方 `falsifier` 设计、命令由总控代跑**（只读围栏下无 shell，见 `GAP-005`）——此即 D3「判据不得自审」的落地：**设计者不是写守卫的人**。**以下读数由台账维护方在本机 `%TEMP%` 沙箱逐格复跑**，与代跑读数一致。

**① 文件完整性 + 金丝雀在位**：

```
ParseErrors = 0
bytes=16874  first4=35,32,83,116（无 BOM）  CR=0  LF=283
自指行号残留（`:\d{2,3}` 命中数）= 0
Invoke-GitChecked 调用点 = 10   （helper 定义 1 + 调用 9；新增的金丝雀与既有四处同形）
'2>$null' 计数 = 6
canary present = True
sha256 = B2A645A86B329B14E821A1ACE7096E575002932ACC0EFF0D8BFCEDA42E711B9A
```

**② 金丝雀的前提（真 git 必须对两个输入给出**不同**退出码）**：

```
$ git rev-parse --verify --quiet "000…0^{commit}"   -> out=[] exit=1     ← 必失败，退非零
$ git --version                                     -> out=[git version 2.49.0.windows.1] exit=0
```

**读法**：两值**不同**（`1` vs `0`）⇒ 金丝雀对**真** git **有判别力**（不会误伤），这正是它可以安全前置的原因。

**③ 对照侧守卫的**身份**（哈希证明逐字节等于改前版本——不得凭记忆重写）**：

```
改前（金丝雀之前）实测 sha256 = 77C9074A03900E37A5FD8927D116140D31445469391FC88360D2372C123DE9E5  bytes=15657
本轮删除金丝雀块（0-based [196..213]，1-based [197..214]）后重建：
    sha256 = 77C9074A03900E37A5FD8927D116140D31445469391FC88360D2372C123DE9E5  bytes=15657
    BYTE-EXACT? True        canary present in it? False
```

> ⚠️ **一次脚手架自伤（如实记录）**：**第一次**重建的切片端点算错（多删/少删了块外的空行），得 `sha256 = D0B04A97…` **≠** `77C9074A…`。**当时判为「对照无效」并拒用**，重算切片后才得 `BYTE-EXACT? True`。**教训**：凡"删掉某段再跑"的对照，**必须用哈希证明重建物等于改前版本**——否则对照格本身就是新的漂移源（与 D.3/D.6 两次清理险情同源）。

**④ 金丝雀两格（每格先自证"跑的是 shim"再判分）**：

```
自证（`Get-Command git` 指向哪一份）：
  CONST   Source=…\gap015c-const-…\git.cmd   is-shim=True   bytes=69
          git --version out=[deadbeef…(40 hex)] exit=0      canary call out=[deadbeef…] exit=0
  EMPTY0  Source=…\gap015c-empty0-…\git.cmd  is-shim=True   bytes=22
          git --version out=[] exit=0                       canary call out=[] exit=0

CANARY-pre (对照，守卫 sha256=77C9074A…)  -> exit=0  stdout=[]  stderr=[]          ← 缺陷本尊：静默
CANARY-new (本轮守卫)                     -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 退出码不可信（对必定失败的输入仍返回 0）。…]
EMPTY0-pre (对照)                         -> exit=0  stdout=[]  stderr=[]          ← 缺陷本尊：静默
EMPTY0-new (本轮守卫)                     -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 退出码不可信…]
```

**读法（两条）**：① **两格均"由静默变为可见"**（`exit=0` 无输出 → `exit=1` + stderr），**同环境、同页、同错 SHA，只差守卫版本**（对照侧哈希已证）⇒ 该静默**确由"退出码不可信"引起**，金丝雀**关上了它**。② **`EMPTY0` 是新增覆盖面**——该 shim **输出为空**，此前只在**正探针**处被"取真值"的旧判据误报（D.15 的 `A4-c`）；换成退出码判据后它**通过正探针**（`exit=0`），**只剩金丝雀能抓**——**这正是"只靠正探针不够"的直接实证**。

**⑤ 其余各格回归（判据未被金丝雀削弱）**：

```
POS-canary  页与 HEAD 一致（正确页）  -> exit=0  stdout=[]  stderr=[]                    静默 ✔
NEG-canary  页 SHA 错                 -> exit=0  stdout=[{"decision":"block",…"而当前是 e2b4a2e"…}]  有牙 ✔
A1-new      0 字节 git.exe 在首位     -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 不可用…]     ✔（正探针挡）
V13-new     恒 128 + 打印 banner      -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 不可用…]     ✔（正探针挡）
FIX-new     剥 git 的 PATH            -> exit=1  stderr=[进度页守卫未运行：PATH 上的 git 不可用…]     ✔
```

**读法**：`A1` / `V13` 都被**正探针**挡在**金丝雀之前**（stderr 是「**不可用**」而非「**退出码不可信**」）⇒ 金丝雀**没有改变**既有各格的行为；`NEG` 仍 `decision:block`、`POS` 仍静默 ⇒ **判据未被削弱**（`AGENTS.md` §5「用例② 仍有牙」的口径）。**注意 `V13` 的挡点变了**：`e2b4a2e` 版是被**下游字符串比较**放过（静默），本轮是被**正探针**拦下（可见）——**两处不同机制、同一可见结果**。

**⑥ `PATHEXT` 优先级（复跑者须知，本轮独立复现）**：

```
$env:PATHEXT = .COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.CPL
同一目录内同时放 0 字节 git.exe 与可用的 git.cmd：
    Get-Command git -> …\git.exe     （.EXE 先于 .CMD）
    git --version   -> THREW:ApplicationFailedException
对照：同目录只放 git.cmd：
    Get-Command git -> …\git.cmd     is the .cmd shim? True
    git --version   -> out=[SHIM-RAN] exit=0
```

**读法**：`PATHEXT` 中 `.EXE` **排在 `.CMD` 之前** ⇒ **同一目录里若残留一个 0 字节 `git.exe`，它会在 `.cmd` shim 之前被选中**，于是"我明明放的是 shim"**看着像没生效**。**故每个 shim 必须独占一个目录**，且**每格先自证 `(Get-Command git).Source` 指向该 shim**——否则整块读数作废（本项目已多次因"未自证"而误判）。

**⑦ 本仓只读探针 + 清理复核（无残留）**：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空）  stderr 空  guard exit=0                      <- 页与 HEAD 一致 ⇒ 非净回归
pointer sha256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10/D.12/D.13/D.14/D.15 一致）
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
page    sha256 = FCF35FA8D66F665EBD9F43078D8B9F2C121D3FE9EDB41BC0D653AF5CBF9D8362   （探针前后一致）
leftover gap015* sandbox dirs = 0     leftover gap015* files = 0
$ git status --porcelain
 M .claude/hooks/check-progress.ps1
 M docs/ledger.md
```

**⑧ 进度页待同步项（`project-progress.html`，**由总控在提交后自行更新**；本节只列清单）**：

| 项 | 需要改成什么 |
| --- | --- |
| 状态条 `head` | 提交后的实际短 SHA（**本轮工作树 HEAD 仍是 `e2b4a2e`，改动未提交**——故**现在写任何值都会不一致**） |
| `GAP` 表 | 新增 `GAP-015`（`已解除`）· `GAP-016`（`未解除`） |
| `DEFER` 表 | 新增 `DEFER-004` |
| 提交数 | 提交后 +1 |
| 时间线 | 补本轮一行（结构性修复 + 金丝雀） |
| 守卫状态描述 | 「判据用真值/字符串」→「**判据一律取退出码 + 负向金丝雀**」 |

> **本表不是页面本身**（D4）：`AGENTS.md` §5 要求 `record.md` 与进度页**同轮更新**；本轮由**总控**负责页面，本节只保证**清单不漏项**。


