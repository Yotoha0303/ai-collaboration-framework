# 进度页守卫 · 隔离沙箱自测（D3 实操）

> 🚀 **一键可跑形态（推荐）**：[`../.claude/hooks/self-test.ps1`](../.claude/hooks/self-test.ps1)
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/self-test.ps1
> ```
> **共 29 格**：**A 组**（进度页守卫 11 格，含 unborn 与 GIT_DIR 劫持）· **B 组**（编号守卫 2 格）· **C 组**（规则投影机械检查 5 格 + 判据词 4 锚点）· **D 组**（双运行时对等 3 格）· **E 组**（进度页投影完整性 2 格）· **F 组**（角色只读围栏 2 格）。
> 本文件下面只详述 **A 组**（进度页守卫的最小两格）；其余见 `delivery-gates.md` §一之二 与脚本内注释。
> **退出码 0 = 全部符合预期；1 = 至少一格不符。**沙箱建在系统临时目录、跑完自删，不触碰工作树。
>
> ⚠️ **它本身也经过负向验证**（D3：自测不能是死代码）：把 `check-progress.ps1` 换成
> `exit 0` 的空壳后跑自测 → **`A1` FAIL、退出码 1**；对 `C1`–`C5` **逐格注入故障**（多插一节 /
> 判据词改写 / 表格断列 / `-E`+`\|` / 幻影编号）→ **各自 FAIL**；还原后 **29/29 PASS**。
> **实测耗时约 `12 s`**（沙箱格 × 每格一次 `powershell.exe` 启动；C/D 组不启沙箱）。
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

> **取材与边界**：本文件的脚本**不含任何项目专有内容**（无路径、无编号、无业务事实），
> 沙箱建在系统临时目录、**不触碰你的工作树**；副本守卫**只读**，不改任何文件。
