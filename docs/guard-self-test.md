# 进度页守卫 · 隔离沙箱自测（D3 实操）

> 🚀 **一键可跑形态（推荐）**：[`../.claude/hooks/self-test.ps1`](../.claude/hooks/self-test.ps1)
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/self-test.ps1
> ```
> **共 45 格**：**A 组**（进度页守卫 13 格，含 unborn · `GIT_DIR` 劫持 · **`A12`/`A13` 比对主干而非当前 `HEAD`**）· **B 组**（编号守卫 2 格）· **C 组**（规则投影 19 格 = `C1`×3 + `C2`×11 锚点 + `C3`–`C7`）· **D 组**（双运行时对等 4 格，含 `D4` 接入引导指针）· **E 组**（投影与运行态一致性 5 格，含 `E5` `memory.md` 业务仓行）· **F 组**（角色只读围栏 2 格）。
> 本文件下面只详述 **A 组**（进度页守卫的最小两格）；其余见 `delivery-gates.md` §一之二 与脚本内注释。
> **退出码 0 = 全部符合预期；1 = 至少一格不符。**沙箱建在系统临时目录、跑完自删，不触碰工作树。
>
> ⚠️ **它本身也经过负向验证**（D3：自测不能是死代码）：把 `check-progress.ps1` 换成
> `exit 0` 的空壳后跑自测 → **`A1` FAIL、退出码 1**；对 `C1`–`C5` **逐格注入故障**（多插一节 /
> 判据词改写 / 表格断列 / `-E`+`\|` / 幻影编号）→ **各自 FAIL**；还原后 **29/29 PASS**
> （**`29/29` 是当时的格数，不是现值**——现值见本节开头的「共 45 格」；按 `AGENTS.md` §5「历史快照不改写」保留）。
> **实测耗时约 `21 s`**（沙箱格 × 每格一次 `powershell.exe` 启动；C/D 组不启沙箱）。
> **⇒ 刻意【不】挂进 `Stop` 钩子**：现有两钩子超时 15s/20s，每轮再加 12s 不划算，
> 且在慢机器上会顶到超时。**它是「改守卫 / 改规则后跑一次」的门禁命令**（见 `delivery-gates.md`），
> 不是每轮都跑的守卫。**这个取舍是显式的——若你愿意付出每轮 12s，可以把它挂上（`DEFER-014`）。**

> **本文件是 `AGENTS.md` §5「验证必须跑两个用例」的可照抄执行形态**，按需读取。
> **规则权威源仍是 `AGENTS.md` §5**；与本文件冲突时以它为准（D4）。
> 用例的完整版（含指针异常 / 剥 PATH / 40 位 SHA / 假 `.git` 各格）见
> `docs/ledger-evidence/ledger-appendix-c.md` 的 **C.2**；**下面只做进度页守卫的最小两格**。

---

## 一、为什么不能在当前工作树里直接跑

`check-progress.ps1` 是 **fail-closed** 判据：它的分支里有一半是**刻意静默**的
（缺页静默 · 找不到 SHA 标记静默 · 仓无 HEAD 静默）。因此**"它没吭声"不构成任何证据**——
「确无判据」与「脚本已死」**在观测上不可分**（台账 `GAP-002`）。

而在**当前工作树**里跑，两个用例都拿不到干净读数：

| 你 | 直接跑守卫会看到 | 为什么这不是干净的实验 |
| --- | --- | --- |
| **clone 本仓的读者** | 静默、无输出 | 运行态（进度页）**不随仓库分发** ⇒ 命中**缺页分支**。那是**用例①**，不是② |
| **在维护者工作树里** | 多半 emit `decision:block` | 页面记的是**旧 SHA** ⇒ 只是**复读现状**，并没有注入任何东西 |

**干净的读数只能来自一个你知道其 HEAD、且页面是你自己写进去的沙箱。**

---

## 二、脚本（整段复制粘贴即可跑）

```powershell
# 1) 造隔离沙箱：临时目录 + .claude/{hooks,progress-page.txt} + 一份守卫副本
$tmp = Join-Path $env:TEMP ('guard-self-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path (Join-Path $tmp '.claude/hooks') -Force | Out-Null
Copy-Item .claude/hooks/check-progress.ps1 (Join-Path $tmp '.claude/hooks/check-progress.ps1')
Set-Content -LiteralPath (Join-Path $tmp '.claude/progress-page.txt') -Value 'project-progress.html' -Encoding utf8
Set-Content -LiteralPath (Join-Path $tmp 'seed.txt') -Value 'seed' -Encoding utf8

# 2) 沙箱必须是一个「能取到 HEAD」的真仓——否则走的是 unborn 静默分支（GAP-012），两个用例都只剩静默
git -C $tmp init -q
git -C $tmp add -A
git -C $tmp -c user.email=a@b -c user.name=demo commit -q -m seed
$head = git -C $tmp rev-parse --short HEAD
"$tmp  HEAD=$head"

# 3) 用例① 缺页 -> 必须【静默 exit 0】（无任何输出）
$o = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp '.claude/hooks/check-progress.ps1')
"case1 exit=$LASTEXITCODE stdout=[$o]"

# 4) 用例② 页面【存在】且写错误 SHA -> 必须 emit {"decision":"block"}
Set-Content -LiteralPath (Join-Path $tmp 'project-progress.html') `
  -Value '<html><body><div>head <b>0000000</b></div></body></html>' -Encoding utf8
$o = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp '.claude/hooks/check-progress.ps1')
"case2 exit=$LASTEXITCODE stdout=[$o]"

# 5) 清理（沙箱是临时目录，删掉即净；不进你的工作树）
Remove-Item -Recurse -Force $tmp
```

---

## 三、实测读数（`2026-10-12`，Windows PowerShell 5.1 · 守卫 sha256 `B2A645A8…11B9A`）

```
$tmp  HEAD=b752018
case1 exit=0 stdout=[]
case2 exit=0 stdout=[{"decision":"block","reason":"进度页落后于仓库：project-progress.html 记录的 HEAD 是 0000000，而当前是 b752018。请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"}]
```

> **`HEAD=b752018` 是那次沙箱自己的提交**，每次跑都不同；`reason` 里的两个 SHA 也随之变。
> **判据是格式与分支，不是这两个 SHA 的字面值**。
> ⚠️ **文案已变（`2026-10-17`，`GAP-031`）**：上面是**当时的实测原文**（按 §5「历史快照不改写」保留）。
> 现行 `reason` 的起句是 **`进度页落后于主干：…，而 <干线名> 是 <SHA>。`**——比对对象已从
> 「当前检出的 HEAD」改为「主干」，故文案必须点名**比的是哪条线**（`origin/main` / `main` / `HEAD（未找到主干）`）。

**对照格（同一沙箱、页面写对 SHA）**：`exit=0`、**stdout 为空**——证明这条守卫
**不是只会喊"block"**，它在一致时确实静默。

---

## 四、读法（为什么两个用例必须一起跑）

| 观察 | 只跑它 | 两个一起跑 |
| --- | --- | --- |
| ② emit `decision:block` | 证明**注入被抓住** | 证明**注入被抓住** |
| ① 静默、`exit 0` | **什么也证明不了**（与死代码同形） | 在 ② 有牙的前提下，① 的静默才可读作「**确无判据**，放行是对的」 |

**推论（D3 的实操形态）**：对**失败即静默**的判据，"它在正常情况下没报警"**永远不是证据**——
必须先让它在**你确信该报警的输入**上报警，它的沉默才开始携带信息。

> ⚠️ **别用退出码判断它有没有牙**：block 路径是 **`exit 0` + stdout 的 JSON**
> （`exit 1` 留给「只提示不阻断」的两条通道）。判据要看**对的那条通道**（D1）。
>
> ⚠️ **改页名后必须重跑这两格**：页名由 `.claude/progress-page.txt` 一行指定，
> 改名就是改那一行（`AGENTS.md` §5）。**残余风险**：指针**指向一个不存在的页名**时守卫仍静默——
> 它与"尚未初始化"不可分，是**已接受的代价**（台账 `GAP-002`）。

---

## 五、接入引导新增的 5 格判据（分属 4 类，`2026-10-25`，issue #55）

首次运行引导（`ONBOARDING.md` / `ONBOARDING.en.md`）落地时，判据层同步补了 5 格。它们与 A 组无关，
**都不启沙箱**、只读工作区，故几乎不耗时。

| 格 | 检查什么 | 为什么它必须存在 |
| --- | --- | --- |
| **`C1` 第三对** | `ONBOARDING.md` 与 `ONBOARDING.en.md` 的**章节数相等** | 引导是双语成对分发的：只改一侧，另一侧读者会拿到**少了一步**的流程，而没有任何东西会响 |
| **`C2` 锚点 +2** | `接入确认` / `attach check` · `现状基线` / `status baseline` 两侧各在场 | `C1` 只数标题。把「接入确认」整条删掉、同时删掉对应英文节，**章节数照样相等** ⇒ 必须靠判据词锚点钉住语义 |
| **`D4` 入口指针** | `CLAUDE.md` 与 `GEMINI.md` **均存在**、**均含 `ONBOARDING.md` 指针**、且**均不得** `@` 导入它 | ① 入口若不提它，引导**存在但无人被指向**——这种缺失不会响；② `@ONBOARDING.md` 会让引导**变常驻**，直接推翻「`AGENTS.md` 常驻、其余按需读」的体量预算（`DEFER-008`）。两种形态（裸路径 `@ONBOARDING.md` 与链接式 `@[label](ONBOARDING.md)`）都挡 |
| **`E5` 业务仓行** | `memory.md` 首条 `^业务仓：(.*)$` 的捕获 = 工作区根下**含 `.git` 的子目录**名（排序后 `, ` 连接；**零个 ⇒ `未接入`**） | 「接入了哪些业务仓」是**文件系统里可实测的事实**，而 `memory.md` 是**手写投影**。两处不同成熟度时读者按旧清单行事——与 `E3`/`E4` 同一族（手写数字 vs 实测），该类已真实咬过三次 |

**`E5` 为什么要放在页面条件块之外（关键，别"顺手整理"回去）**：
`E1`/`E3`/`E4`/`E2` 整组包在 `if (-not $pagePath -or -not (Test-Path $pagePath)) { SKIP } else { … }` 里，
因为**它们读的是进度页**。而 `E5` **只读 `memory.md`，与进度页毫无关系**。
若把它放进那个 `else` 块，**页面不存在时它会被一起 `SKIP`** ⇒ 一个与页面无关的判据
**因页面缺失而永不执行**，且"跳过"在观测上与"检查过了"同形（D3）。
讽刺的是**页面缺失恰是新项目首次使用的常态**——那时正是最需要这条判据的时候。
（该缺陷形态已在 `GAP-028` 登记：`SKIP` 分支不增加 `PASS`/`FAIL`，会让总格数变小。）

**四个格的负向用例（D3，逐格注入、实际跑过）**：

| 注入 | 期望 |
| --- | --- |
| 把 `ONBOARDING.en.md` 改名 ⇒ | `C1 ONBOARDING` **FAIL**（双语文件缺失） |
| 在 `CLAUDE.md` 临时加一行 `@ONBOARDING.md` ⇒ | `D4` **FAIL**（命中 `@` 导入） |
| 把 `memory.md` 的「业务仓：」行改成不存在的路径 ⇒ | `E5` **FAIL**（记忆值 ≠ 实测值） |
| 把任一处 `45` 改回 `40` ⇒ | `C6` **FAIL**（总数陈述与实测格数不符） |

> ⚠️ **`E5` 的当前状态如实记**：本仓**零业务子仓**，实测值应为 `未接入`；
> 若 `memory.md` 尚无「业务仓：」行，`E5` 会 **FAIL 并打印实测值**（缺行 = 投影缺失，不是合法状态，
> 与 `AGENTS.md` §4.0「① 必须留一行」同源）。补上该行即转 PASS——**这是待补的投影，不是脚本的缺陷**。

---

> **取材与边界**：本文件的脚本**不含任何项目专有内容**（无路径、无编号、无业务事实），
> 沙箱建在系统临时目录、**不触碰你的工作树**；副本守卫**只读**，不改任何文件。
