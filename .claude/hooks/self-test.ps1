# 守卫自测 · 一键可跑（D3 实操）
#
# 本脚本是 `docs/guard-self-test.md` 的【可执行形态】：把两格手动沙箱
# 扩成【两守卫 × 正/负控】，整段复制粘贴或直接 `-File` 跑，**只读、不碰你的工作树**。
#
# 为什么必须跑这一组：两个守卫都含【刻意静默】的分支（缺页 / 找不到 SHA 标记 /
# 无候选仓 / unborn 仓）。"它没吭声"**不构成任何证据**——「确无判据」与「脚本已死」
# 在观测上不可分（台账 `GAP-002`）。**必须先让它在「你确信该报警」的输入上报警**，
# 它的沉默才开始携带信息。本脚本就是造那组输入。
#
# 退出码：0 = 全部格子符合预期；1 = 至少一格不符（即守卫可能已瞎）。
#
# 规则权威源仍是 `AGENTS.md` §5；与本脚本冲突时以它为准（D4）。

[CmdletBinding()]
param(
    # 跑完保留沙箱目录以便查看（默认删除）
    [switch]$KeepSandbox
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 基础设施
$HookDir = Split-Path -Parent $PSCommandPath          # <repo>/.claude/hooks
$RepoRoot = Split-Path -Parent (Split-Path -Parent $HookDir)
$ProgressGuard = Join-Path $HookDir 'check-progress.ps1'
$NumbersGuard  = Join-Path $HookDir 'check-numbers.ps1'

foreach ($g in @($ProgressGuard, $NumbersGuard)) {
    if (-not (Test-Path -LiteralPath $g)) { Write-Error "缺守卫：$g"; exit 1 }
}

$script:Pass = 0
$script:Fail = 0

function New-Sandbox {
    param([string]$Tag)
    $d = Join-Path $env:TEMP ('guard-selftest-' + $Tag + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $d '.claude/hooks') -Force | Out-Null
    Copy-Item -LiteralPath $ProgressGuard (Join-Path $d '.claude/hooks/check-progress.ps1')
    Copy-Item -LiteralPath $NumbersGuard  (Join-Path $d '.claude/hooks/check-numbers.ps1')
    # 页名指针（页名的唯一事实源）
    [System.IO.File]::WriteAllText((Join-Path $d '.claude/progress-page.txt'), "project-progress.html`n")
    # 沙箱必须是一个【能取到 HEAD】的真仓 —— 否则走 unborn 静默分支（GAP-012），两格都只剩静默
    git -C $d init -q
    [System.IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
    git -C $d add -A
    git -C $d -c user.email=a@b -c user.name=demo commit -q -m seed
    return $d
}

function Invoke-Guard {
    param([string]$Script, [string]$Sandbox)
    # ⚠️ 本函数【必须】在作用域内把 EAP 降到 Continue 后再调原生命令。
    # 不加这一句，PS 5.1 会把 powershell.exe 的 stderr 经 2>&1 包成
    # NativeCommandError（ErrorRecord），而脚本级 `$ErrorActionPreference='Stop'`
    # 会把它升格为【终止异常】——于是「守卫报了撞车」反而把自测脚本自己打断。
    # 这正是本仓台账 GAP-013② 同族的坑（作用域 EAP 与「原生命令写 stderr」的交互）；
    # 修法与 `check-progress.ps1` 的 `Invoke-GitChecked` 一致：把 EAP 收进子作用域。
    $raw = & {
        $ErrorActionPreference = 'Continue'
        powershell -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1
    }
    return [pscustomobject]@{
        Exit   = $LASTEXITCODE
        Stdout = ([string]::Join("`n", @($raw))).Trim()
    }
}

function Assert-Cell {
    param([string]$Name, [string]$Expect, $Actual, [scriptblock]$Predicate)
    $ok = & $Predicate
    if ($ok) { $script:Pass++; "  PASS  $Name" }
    else { $script:Fail++; "  FAIL  $Name`n        期望：$Expect`n        实测：$($Actual.Exit) / [$($Actual.Stdout)]" }
}

"守卫自测 · 工作区根 = $RepoRoot"
"守卫 sha256:"
foreach ($g in @($ProgressGuard, $NumbersGuard)) {
    "  $(Split-Path -Leaf $g)  $((Get-FileHash -LiteralPath $g -Algorithm SHA256).Hash.Substring(0,8))…"
}
""

# ================================================================ A · 进度页守卫
# A1 正控（有牙）：页面【存在】且写错 SHA -> 必须 emit decision:block
# A2 对照：页面存在且写对 SHA -> 必须静默（证明它不是只会喊 block）
# A3 负控（已接受代价）：指针指向不存在的页名 -> 静默（GAP-002）
# A4 负控（GAP-025）：<b> 上加一个 class 属性 -> 正则失配 -> 静默放行陈旧页
"== A · check-progress.ps1 =="
$sbA = New-Sandbox -Tag 'prog'
try {
    $head = (git -C $sbA rev-parse --short HEAD).Trim()
    $page = Join-Path $sbA 'project-progress.html'

    # A1
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>0000000</b></div></body></html>`n")
    $a1 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A1 正控 页面存在+错SHA → decision:block' -Expect 'stdout 含 {"decision":"block"}' -Actual $a1 `
        -Predicate { $a1.Stdout -match '"decision"\s*:\s*"block"' }

    # A2
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>$head</b></div></body></html>`n")
    $a2 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A2 对照 页面存在+SHA一致 → 静默' -Expect 'exit 0 且 stdout 空' -Actual $a2 `
        -Predicate { $a2.Exit -eq 0 -and $a2.Stdout -eq '' }

    # A3
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>0000000</b></div></body></html>`n")
    [System.IO.File]::WriteAllText((Join-Path $sbA '.claude/progress-page.txt'), "no-such-page.html`n")
    $a3 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A3 负控 指针指向不存在页名 → 静默（GAP-002 已接受代价）' -Expect 'exit 0 且 stdout 空' -Actual $a3 `
        -Predicate { $a3.Exit -eq 0 -and $a3.Stdout -eq '' }
    [System.IO.File]::WriteAllText((Join-Path $sbA '.claude/progress-page.txt'), "project-progress.html`n")

    # A4 —— GAP-025 的【已修】格：正则改为容忍 <b> 上的属性后，
    # 加一个 class 不应再让它失明。（修复前这一格是静默的。）
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b class=""v"">0000000</b></div></body></html>`n")
    $a4 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A4 <b> 加 class 属性 → 仍 block（GAP-025 已修此格）' -Expect 'stdout 含 {"decision":"block"}' -Actual $a4 `
        -Predicate { $a4.Stdout -match '"decision"\s*:\s*"block"' }

    # A5 —— GAP-025 的【残余】格，**故意断言"静默"**：把标记重构成 <span> 后守卫仍失明。
    # 这一格的作用不是"验通过"，而是【把残余钉住】：只要它还静默，GAP-025 就没关；
    # 哪天有人把守卫改成不解析展示层，这一格会开始 FAIL —— 那正是需要更新台账的信号。
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <span>0000000</span></div></body></html>`n")
    $a5 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A5 重构成 <span> → 仍静默（GAP-025 残余，故意断言）' -Expect 'exit 0 且 stdout 空' -Actual $a5 `
        -Predicate { $a5.Exit -eq 0 -and $a5.Stdout -eq '' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbA -ErrorAction SilentlyContinue } }
""

# ================================================================ A6-A8 · unborn 仓（GAP-012）
# 【这两格断言的是"静默是对的"，不是一个待修的行为】——故附对照格，证明该静默是【分支特定】
# 而非死代码。
#
# 为什么维持静默（2026-10-14 读代码后判定，【与台账 GAP-012 原写的解除条件相反】）：
#   ① unborn 仓【没有 HEAD】⇒ 页面无法"落后"一个不存在的 HEAD ⇒【根本没有判据】。
#      通知它 = 通知"判据不存在"——而那正是指针异常通道的职责，在此处价值更低。
#   ② 代价落在最坏位置：新用户从零建仓时，页面尚未存在且无提交；若 unborn 变成通知，
#      他们会在【第一次提交之前的每一轮】收到警告 —— 恰在入门时刻制造噪声。
#   ③ 该状态是【过渡性且自愈】的：首次提交即消失。
# ⇒ 台账原写的解除条件「显式识别 unborn 并 emit 提示而非静默」【提错了】；已在台账留痕更正。
# 但仍【缺负向验证】（D3 要求）—— 这三格就是补它。
$sbU = Join-Path $env:TEMP ('unborn-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path (Join-Path $sbU '.claude/hooks') -Force | Out-Null
    Copy-Item -LiteralPath $ProgressGuard (Join-Path $sbU '.claude/hooks/check-progress.ps1')
    [System.IO.File]::WriteAllText((Join-Path $sbU '.claude/progress-page.txt'), "project-progress.html`n")
    git -C $sbU init -q          # 【只 init，不 commit】—— 这一格的全部意义所在

    # A6 前条件：必须【真的】是 unborn，否则这一格测的不是它声称要测的东西
    # ⚠️ 必须把 EAP 收进子作用域：unborn 下 git 把 `fatal: Needed a single revision`
    # 写进 stderr，而脚本级 EAP=Stop 会把它升格为【终止异常】，把自测自己打断。
    # 这正是本仓已记过两次的坑（GAP-013② / 本文件 Invoke-Guard 的注释）——
    # 直接调 git 而不走 Invoke-Guard，就会复现它。
    $unbornExit = & { $ErrorActionPreference = 'Continue'; git -C $sbU rev-parse --short HEAD 2>$null; $LASTEXITCODE }
    Assert-Cell -Name 'A6 前条件 沙箱确实 unborn（rev-parse --short HEAD 非 0）' -Expect 'exit != 0' `
        -Actual ([pscustomobject]@{ Exit = $unbornExit; Stdout = '' }) -Predicate { $unbornExit -ne 0 }

    # A7 页面【存在】且写错 SHA —— 在 unborn 下仍须静默（维持；理由见上）
    [System.IO.File]::WriteAllText((Join-Path $sbU 'project-progress.html'), "<html><body><div>head <b>0000000</b></div></body></html>`n")
    $a6 = Invoke-Guard -Script (Join-Path $sbU '.claude/hooks/check-progress.ps1') -Sandbox $sbU
    Assert-Cell -Name 'A7 unborn 仓 + 页面存在且写错 SHA → 静默（GAP-012 维持）' -Expect 'exit 0 且 stdout 空' `
        -Actual $a6 -Predicate { $a6.Exit -eq 0 -and $a6.Stdout -eq '' }

    # A8 对照：同一沙箱补一次提交后，同页同错 SHA 必须 block
    # ⇒ 证明 A7 的静默是【分支特定】，不是"守卫已死"
    git -C $sbU add -A
    git -C $sbU -c user.email=a@b -c user.name=demo commit -q -m seed
    $a7 = Invoke-Guard -Script (Join-Path $sbU '.claude/hooks/check-progress.ps1') -Sandbox $sbU
    Assert-Cell -Name 'A8 对照 同一沙箱补一次提交后 → 必须 block（证明 A7 是分支特定）' -Expect 'stdout 含 {"decision":"block"}' `
        -Actual $a7 -Predicate { $a7.Stdout -match '"decision"\s*:\s*"block"' }
    # --- A9/A10 · GAP-013①：GIT_DIR 劫持（2026-10-14 实测并修复）
    # 现象（修复前实测）：设 `GIT_DIR` 指向【另一个仓】，守卫会去读那个仓的 HEAD。
    # 若其 HEAD 恰好与页面一致 → exit 0 【静默放行】一个陈旧页。
    # 机制：`git -C <repo>` 指定工作目录，但 `GIT_DIR` 覆盖仓库发现 —— 两者不是一回事。
    # 修法：`Invoke-GitChecked` 在调用前把 `GIT_DIR` 置空、调用后还原（`$env:` 是进程级，
    # 故须 save/restore）。该 helper 是两个守卫的【唯一】git 入口，所以一处即覆盖全部。
    $repoHeadNow = (git -C $RepoRoot rev-parse --short HEAD).Trim()   # 框架仓的 HEAD（≠ 沙箱的）
    $sbHeadNow = (git -C $sbU rev-parse --short HEAD).Trim()
    Assert-Cell -Name 'A9 前条件 沙箱 HEAD 与框架仓 HEAD 不同（否则本格无意义）' -Expect '两者不同' `
        -Actual ([pscustomobject]@{ Exit = $sbHeadNow; Stdout = $repoHeadNow }) -Predicate { $sbHeadNow -ne $repoHeadNow }

    # 页面写【框架仓】的 HEAD —— 对沙箱而言是陈旧的 ⇒ 必须 block
    [System.IO.File]::WriteAllText((Join-Path $sbU 'project-progress.html'), "<html><body><div>head <b>$repoHeadNow</b></div></body></html>`n")

    $t9 = & { $ErrorActionPreference='Continue'; $env:GIT_DIR=$null; powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sbU '.claude/hooks/check-progress.ps1') 2>&1 }
    $s9 = [string]::Join("`n", @($t9)).Trim()
    Assert-Cell -Name 'A10 对照 无 GIT_DIR → block（正控）' -Expect 'stdout 含 {"decision":"block"}' `
        -Actual ([pscustomobject]@{ Exit = 0; Stdout = $s9 }) -Predicate { $s9 -match '"decision"\s*:\s*"block"' }

    # A11 —— GIT_DIR 及【同族环境变量】皆不得改变读数。
    # 2026-10-14 实测：只有 GIT_DIR 会劫持（其余四个【不】劫持）。但判据仍覆盖全族 ——
    # 因为"哪个会劫持"是 git 的实现细节，不该由人记得；判据只该是"没有一个能改变读数"。
    # （`Invoke-GitChecked` 只清 GIT_DIR；其余四个实测无害，故此格是对该取舍的【持续验证】，
    #   而非重复。哪天 git 改了语义，这一格会开始 FAIL。）
    # 合并为【一次】spawn（逐个 spawn 要 5 次 powershell.exe 启动，实测显著抬升整轮耗时）。
    # 判据仍是"没有一个能改变读数"—— 两者皆设时若任一劫持，读数一样会失真（静默），本格照样 FAIL。
    # ⚠️ 取值必须【逐个按语义设】—— 2026-10-14 实测踩过：把五个变量【全设成同一个值】
    # 时该组合【不劫持】，于是这一格对"修复被撤掉"不敏感、塌成死代码（注入验证时抓到的）。
    # 下面这组值是【实测定为会劫持】的那组（GIT_WORK_TREE 指工作树根、GIT_OBJECT_DIRECTORY
    # 指 objects 目录），故它能真正验到"清 GIT_DIR"这一步。
    $envMap = [ordered]@{
        'GIT_DIR'              = (Join-Path $RepoRoot '.git')
        'GIT_WORK_TREE'        = $RepoRoot
        'GIT_OBJECT_DIRECTORY' = (Join-Path $RepoRoot '.git/objects')
        'GIT_COMMON_DIR'       = (Join-Path $RepoRoot '.git')
        'GIT_INDEX_FILE'       = (Join-Path $RepoRoot '.git/index')
    }
    $savedEV = @{}
    foreach ($ev in $envMap.Keys) {
        $savedEV[$ev] = [Environment]::GetEnvironmentVariable($ev)
        [Environment]::SetEnvironmentVariable($ev, $envMap[$ev])
    }
    try {
        $probe = & { $ErrorActionPreference='Continue'; powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sbU '.claude/hooks/check-progress.ps1') 2>&1 }
        $sFam = [string]::Join("`n", @($probe)).Trim()
    } finally {
        foreach ($ev in $envMap.Keys) { [Environment]::SetEnvironmentVariable($ev, $savedEV[$ev]) }
    }
    Assert-Cell -Name 'A11 同族 git 环境变量（5 个）皆不得改变读数（单次 spawn）' -Expect 'stdout 含 {"decision":"block"}' `
        -Actual ([pscustomobject]@{ Exit = 0; Stdout = $sFam }) -Predicate { $sFam -match '"decision"\s*:\s*"block"' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbU -ErrorAction SilentlyContinue } }
""

# ================================================================ B · 编号守卫
# B1 正控（有牙）：两条分支各有同号不同文件 -> exit 1 且 stderr 报撞车
# B2 对照：只有一个 docs/changes/ 条目、无跨分支同号 -> exit 1 且 stderr 报
#          「未检查编号撞车」？不——那条是【无法枚举】的通道。
#          本仓形态是「0 候选仓」：docs/changes/ 不存在于任何 ref -> exit 0 静默。
"== B · check-numbers.ps1 =="
$sbB = New-Sandbox -Tag 'nums'
try {
    $gB = Join-Path $sbB '.claude/hooks/check-numbers.ps1'

    # B1 正控：造跨分支同号撞车
    New-Item -ItemType Directory -Path (Join-Path $sbB 'docs/changes') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $sbB 'docs/changes/023-alpha.md'), "alpha`n")
    git -C $sbB add -A
    git -C $sbB -c user.email=a@b -c user.name=demo commit -q -m 'a: 023-alpha'
    git -C $sbB checkout -q -b feat-b
    Remove-Item -LiteralPath (Join-Path $sbB 'docs/changes/023-alpha.md') -Force
    [System.IO.File]::WriteAllText((Join-Path $sbB 'docs/changes/023-beta.md'), "beta`n")
    git -C $sbB add -A
    git -C $sbB -c user.email=a@b -c user.name=demo commit -q -m 'b: 023-beta'
    git -C $sbB checkout -q master 2>$null; if ($LASTEXITCODE -ne 0) { git -C $sbB checkout -q main }

    $b1 = Invoke-Guard -Script $gB -Sandbox $sbB
    Assert-Cell -Name 'B1 正控 跨分支同号不同文件 → exit 1 + 报撞车' -Expect 'exit 1 且 stdout 含「撞车」' -Actual $b1 `
        -Predicate { $b1.Exit -eq 1 -and $b1.Stdout -match '撞车' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbB -ErrorAction SilentlyContinue } }

$sbC = New-Sandbox -Tag 'nocand'
try {
    # B2 对照：任何 ref 都没有 docs/changes/ -> 0 候选仓 -> exit 0 静默
    $b2 = Invoke-Guard -Script (Join-Path $sbC '.claude/hooks/check-numbers.ps1') -Sandbox $sbC
    Assert-Cell -Name 'B2 对照 无 docs/changes/（0 候选仓）→ 静默' -Expect 'exit 0 且 stdout 空' -Actual $b2 `
        -Predicate { $b2.Exit -eq 0 -and $b2.Stdout -eq '' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbC -ErrorAction SilentlyContinue } }
""

# ================================================================ C · 规则—判据之间的机械检查
# 这四格补的是台账 GAP-017 同族里【可机械检出】的四名。它们不起沙箱，直接查工作区。
# 之所以放这里而不是新开脚本：它们与 A/B 同属「D3 负向用例先行」这一件事——
# 判据的牙要有人定期去咬，规则的投影也要有人定期去对。
"== C · 规则投影的机械检查（GAP-017 同族）=="

function Get-BilingualPairs {
    return @(
        [pscustomobject]@{ Zh = 'AGENTS.md'; En = 'AGENTS.en.md'; Name = 'AGENTS' },
        [pscustomobject]@{ Zh = 'README.md'; En = 'README.en.md'; Name = 'README' }
    )
}

# --- C1 · 双语章节结构（GAP-022 的判据）
# 单测这一格【不充分】：它只证明「节的数目与层级对上了」，证明不了「内容等价」。
# 故 C2 必须一起跑 —— 这与 A1/A2 是同一个道理（结构绿 ≠ 内容绿）。
foreach ($p in Get-BilingualPairs) {
    $zhFile = Join-Path $RepoRoot $p.Zh
    $enFile = Join-Path $RepoRoot $p.En
    if (-not (Test-Path -LiteralPath $zhFile) -or -not (Test-Path -LiteralPath $enFile)) {
        $script:Fail++; "  FAIL  C1 $($p.Name) 双语文件缺失"
        continue
    }
    $zh = @(Select-String -LiteralPath $zhFile -Pattern '^#{2,3} ').Count
    $en = @(Select-String -LiteralPath $enFile -Pattern '^#{2,3} ').Count
    Assert-Cell -Name "C1 $($p.Name) 双语章节数相等（zh=$zh en=$en）" -Expect '两数相等' -Actual ([pscustomobject]@{ Exit = $zh; Stdout = $en }) `
        -Predicate { $zh -eq $en }
}

# --- C2 · 判据词双语锚点（F7 建议的最小内容判据）
# 为什么必须有它：C1 全绿时，把英文版 all three must hold 改成 any one may hold、
# 并整条删掉硬边界③，C1 照样全绿（已实测）。**结构判据测不出语义反转。**
# 本格检查几条【承载硬约束】的判据词在中英两侧各自在场。
# ⚠️ 它只判【在场】，不判【次数相等】——两侧提及次数可以不同（英文可能换一种措辞说到同一件事）。
#    这条限制是显式的：它把盲区从「任意语义反转」收窄到「判据词整体消失」，**不等于内容等价**。
$anchors = @(
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '三条同时成立';   En = 'AGENTS.en.md'; EnWord = 'all three must hold' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '不构成豁免';     En = 'AGENTS.en.md'; EnWord = 'Not an exemption' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '历史快照不改写'; En = 'AGENTS.en.md'; EnWord = 'historical snapshots are not rewritten' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '任务定位协议';   En = 'AGENTS.en.md'; EnWord = 'Task-location protocol' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '决策提醒义务';   En = 'AGENTS.en.md'; EnWord = 'Decision-reminder duty' }
)
foreach ($a in $anchors) {
    $zc = @(Select-String -LiteralPath (Join-Path $RepoRoot $a.Zh) -Pattern ([regex]::Escape($a.ZhWord)) -AllMatches).Count
    $ec = @(Select-String -LiteralPath (Join-Path $RepoRoot $a.En) -Pattern ([regex]::Escape($a.EnWord)) -AllMatches).Count
    Assert-Cell -Name "C2 判据词双语在场：「$($a.ZhWord)」/「$($a.EnWord)」（$zc/$ec）" -Expect '两侧均 >0' `
        -Actual ([pscustomobject]@{ Exit = $zc; Stdout = $ec }) -Predicate { $zc -gt 0 -and $ec -gt 0 }
}

# --- C3 · Markdown 表格列数一致（GAP-017 同族第 ③ 名）
# 为什么要有它：表格是规则的载体。删掉行首一个 `| ` 会让三列塌成两列，
# 渲染时「判据」列被吞进「分路」列 —— 规则静默变形，两条 Stop 钩子均静默（已实测）。
# 数法：把 \| （转义管道）先换成占位符，再按 | 切。
$tableFiles = @(git -C $RepoRoot ls-files '*.md')
$tableCount = 0; $tableBad = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $lines = [System.IO.File]::ReadAllLines($fp)
    $inTable = $false; $expect = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if ($l -match '^\|') {
            $s = $l -replace '\\\|', '@ESC@'
            $cells = ($s -split '\|').Count - 2
            if (-not $inTable) { $inTable = $true; $expect = $cells; $tableCount++ }
            elseif ($cells -ne $expect) { $tableBad += "$f`:$($i+1) 列数=$cells 期望=$expect" }
        } else { $inTable = $false }
    }
}
Assert-Cell -Name "C3 Markdown 表格列数一致（$tableCount 张表）" -Expect '异常行 = 0' `
    -Actual ([pscustomobject]@{ Exit = $tableBad.Count; Stdout = ($tableBad -join '; ') }) -Predicate { $tableBad.Count -eq 0 }

# --- C4 · git grep 的 -E 与 \| 同现（GAP-017 同族第 ⑤ 名）
# -E 是 ERE，其中 \| 是【字面竖线】而非【或】 ⇒ 命令照抄跑出 0 行，而记录声称有命中。
# 它不报错，只返回空。
# 豁免：行内含 `grep-pipe-trap: 引用反例` 标记的，是【刻意展示的错误示例】，不算误用。
$grepBad = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $lines = [System.IO.File]::ReadAllLines($fp)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match 'grep-pipe-trap') { continue }
        foreach ($m in [regex]::Matches($l, 'git\s+grep[^\x60]*')) {
            if ($m.Value -match '\-[a-zA-Z]*E' -and $m.Value -match '\\\|') {
                $grepBad += "$f`:$($i+1)  $($m.Value.Trim())"
            }
        }
    }
}
Assert-Cell -Name 'C4 git grep -E 与 \| 不同现' -Expect '误用 = 0' `
    -Actual ([pscustomobject]@{ Exit = $grepBad.Count; Stdout = ($grepBad -join '; ') }) -Predicate { $grepBad.Count -eq 0 }

# --- C5 · 编号引用完整性（防幻影引用）
# 形状：文档里写了 GAP-099 / DEFER-099 之类，而台账里根本没有那一条。
# 读者照着编号去台账查 —— 查不到，而他不会知道是编号错了还是自己看错了。
# 本仓真实发生过一次（GAP-016 幻影路径），且总控本轮写文档时差点再犯一次（引用尚未登记的 DEFER-014）。
# 数法：全仓 tracked 文件里出现的 GAP-NNN / DEFER-NNN，逐个到 docs/ledger.md 里找定义行。
$ledgerPath = Join-Path $RepoRoot 'docs/ledger.md'
$defined = @{}
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($ledgerPath), '^\|\s*\*\*`?(GAP|DEFER)-(\d{3})`?\*\*', 'Multiline')) {
        $defined["$($m.Groups[1].Value)-$($m.Groups[2].Value)"] = $true
    }
}
$phantom = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $txt = [System.IO.File]::ReadAllText($fp)
    foreach ($m in [regex]::Matches($txt, '\b(GAP|DEFER)-(\d{3})\b')) {
        $id = "$($m.Groups[1].Value)-$($m.Groups[2].Value)"
        if (-not $defined.ContainsKey($id)) { $phantom += "$f → $id" }
    }
}
$phantom = @($phantom | Sort-Object -Unique)
Assert-Cell -Name "C5 编号引用完整（台账定义了 $($defined.Count) 条）" -Expect '幻影引用 = 0' `
    -Actual ([pscustomobject]@{ Exit = $phantom.Count; Stdout = ($phantom -join '; ') }) -Predicate { $phantom.Count -eq 0 }

# ================================================================ D · 双运行时对等（GAP-026 ②）
# Claude Code 与 Antigravity 走两个入口、两套挂载。二者【刻意不完全相同】（见 D2），
# 但"刻意不同"必须是【声明过的不同】——否则哪天有人为了"对齐"把 AGENTS.md 加进 GEMINI.md，
# 就会撞上 24KB 截断，而那个静默失效正是 GAP-023 踩过的坑。
"== D · 双运行时对等（GAP-026 ②）=="

function Get-HeadingLines {
    param([string]$Path)
    $p = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @(Select-String -LiteralPath $p -Pattern '^#{2,3} ' | ForEach-Object { $_.Line })
}

# --- D1 · 两入口章节数相等（GEMINI.md 自称"与 CLAUDE.md 对等、结构保持一致"）
$zhIn = Get-HeadingLines 'CLAUDE.md'
$enIn = Get-HeadingLines 'GEMINI.md'
Assert-Cell -Name "D1 CLAUDE.md 与 GEMINI.md 章节数相等（$($zhIn.Count)/$($enIn.Count)）" -Expect '两数相等且 >0' `
    -Actual ([pscustomobject]@{ Exit = $zhIn.Count; Stdout = $enIn.Count }) -Predicate { $zhIn.Count -eq $enIn.Count -and $zhIn.Count -gt 0 }

# --- D2 · GEMINI.md 【刻意】不 @ 展开 AGENTS.md
# 为什么断言"没有"：Antigravity 的 user_rules 单文件上限 24,000 B，内联展开 AGENTS.md（>50 KB）
# 会把它静默截断到 24KB（GAP-023 实测）。故 AGENTS.md 走 user_rules + PreInvocation 分片续载。
# 这一格防的是"为了对等而误加 @AGENTS" —— 那会让规则源静默丢一半。
$gi = Join-Path $RepoRoot 'GEMINI.md'
$inlineAgents = 0
if (Test-Path -LiteralPath $gi) {
    $inlineAgents = @(Select-String -LiteralPath $gi -Pattern '@\[?\s*AGENTS' -AllMatches).Count
}
Assert-Cell -Name 'D2 GEMINI.md 【不】@ 展开 AGENTS.md（防 24KB 截断）' -Expect '命中 = 0' `
    -Actual ([pscustomobject]@{ Exit = $inlineAgents; Stdout = '' }) -Predicate { $inlineAgents -eq 0 }

# --- D3 · 守卫用到的退出码 ⊆ stop-adapter 覆盖的退出码
# stop-adapter.ps1 把 Claude Code 的协议翻成 Antigravity 的协议。它显式处理：
#   stdout {"decision":"block"} -> continue（阻断）· exit 1 + stderr -> 透传 + allow（提示）· exit 0 -> allow
# 若某守卫新增一个【未被覆盖】的退出码（如 exit 2），适配器会落到 allow 分支 ——
# 即【新的失败模式被静默放行】。本格就是防这个。
$adapterCovered = @(0, 1)
$guardExits = @{}
foreach ($g in @('check-progress.ps1', 'check-numbers.ps1')) {
    $gp = Join-Path $RepoRoot ('.claude/hooks/' + $g)
    if (-not (Test-Path -LiteralPath $gp)) { continue }
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($gp), 'exit\s+(\d+)')) {
        $guardExits[[int]$m.Groups[1].Value] = $true
    }
}
$uncovered = @($guardExits.Keys | Where-Object { $_ -notin $adapterCovered } | Sort-Object)
Assert-Cell -Name "D3 守卫退出码 ⊆ adapter 覆盖（守卫用 $($guardExits.Keys -join '/')；覆盖 $($adapterCovered -join '/')）" `
    -Expect '未覆盖 = 0' -Actual ([pscustomobject]@{ Exit = $uncovered.Count; Stdout = ($uncovered -join ',') }) `
    -Predicate { $uncovered.Count -eq 0 }

# ================================================================ E · 进度页投影完整性
# 台账是唯一事实源，进度页是它的【展示投影】。投影漏条 → 按页面执行任务的人【直接漏掉任务】，
# 且【漏了不会响】（GAP-022 同族的失效形态）。
# 本类已真实咬过两次：一次是源文件 `[目前不做]` 标记被移除，一次是源文件第 11 条被整条换掉。
"== E · 进度页投影完整性 =="

# 页名由指针文件一行指定（页名的唯一事实源）
$ptrPath = Join-Path $RepoRoot '.claude/progress-page.txt'
$pagePath = $null
if (Test-Path -LiteralPath $ptrPath) {
    $pn = (Get-Content -LiteralPath $ptrPath -Raw -ErrorAction SilentlyContinue)
    if ($pn) { $pn = $pn.Trim() }
    if ($pn) { $pagePath = Join-Path $RepoRoot $pn }
}

if (-not $pagePath -or -not (Test-Path -LiteralPath $pagePath)) {
    # 页面不存在 = 尚未初始化，无判据可言（与守卫同口径，AGENTS.md §5）。**不算失败**。
    "  SKIP  E 组：进度页不存在（尚未初始化），无判据可言"
} else {
    $pageTxt = [System.IO.File]::ReadAllText($pagePath)

    # --- E1 · 页面覆盖全部 GAP-/DEFER- 编号
    # 防的是：台账新增了编号，页面没跟上 —— 读者在页面上看不到它，以为没有。
    $ledgerTxt = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'docs/ledger.md'))
    $allIds = @()
    foreach ($m in [regex]::Matches($ledgerTxt, '^\|\s*\*\*`?(GAP|DEFER)-(\d{3})`?\*\*', 'Multiline')) {
        $allIds += "$($m.Groups[1].Value)-$($m.Groups[2].Value)"
    }
    $allIds = @($allIds | Sort-Object -Unique)
    $pageIds = @()
    foreach ($m in [regex]::Matches($pageTxt, '\b(GAP|DEFER)-\d{3}\b')) { $pageIds += $m.Value }
    $missing = @($allIds | Where-Object { $_ -notin $pageIds })
    Assert-Cell -Name "E1 页面覆盖全部编号（台账 $($allIds.Count) 条）" -Expect '未覆盖 = 0' `
        -Actual ([pscustomobject]@{ Exit = $missing.Count; Stdout = ($missing -join ',') }) -Predicate { $missing.Count -eq 0 }

    # --- E3 · 状态条数字 = 实测
    # 为什么要有它（2026-10-15 补）：E1 查【编号覆盖】、E2 查【待办条数】，都【抓不到状态条过期】——
    # 而状态条正是读者第一眼看的「当前是什么状态」。实测踩过：页面写「提交 88 / 入库 51」，
    # 实测为 87 / 52（新增 docs/planning/ 后入库数变了，而「提交」是我按"加一"写的、没实测）。
    # 这条把「head / 提交 / 入库」三项都钉到实测上——它们是 D1 所说"必须当场量的"那一类数字。
    $barHead = [regex]::Match($pageTxt, '<div>head <b>([0-9a-fA-F]{7,40})</b>[^<]*</div>')
    $barComm = [regex]::Match($pageTxt, '<div>提交 <b>(\d+)</b>[^<]*</div>')
    $barFile = [regex]::Match($pageTxt, '<div>入库 <b>(\d+)</b>[^<]*</div>')
    $realHead = (git -C $RepoRoot rev-parse --short HEAD).Trim()
    $realComm = (git -C $RepoRoot rev-list --count HEAD).Trim()
    $realFile = (git -C $RepoRoot ls-files | Measure-Object).Count
    $barBad = @()
    if (-not $barHead.Success) { $barBad += '状态条缺 head' }
    elseif ($barHead.Groups[1].Value -ne $realHead) { $barBad += "head 页=$($barHead.Groups[1].Value) 实测=$realHead" }
    if (-not $barComm.Success) { $barBad += '状态条缺 提交' }
    elseif ([int]$barComm.Groups[1].Value -ne [int]$realComm) { $barBad += "提交 页=$($barComm.Groups[1].Value) 实测=$realComm" }
    if (-not $barFile.Success) { $barBad += '状态条缺 入库' }
    elseif ([int]$barFile.Groups[1].Value -ne [int]$realFile) { $barBad += "入库 页=$($barFile.Groups[1].Value) 实测=$realFile" }
    Assert-Cell -Name "E3 状态条 head/提交/入库 = 实测" -Expect '不一致 = 0' `
        -Actual ([pscustomobject]@{ Exit = $barBad.Count; Stdout = ($barBad -join '; ') }) -Predicate { $barBad.Count -eq 0 }
    # --- E4 · memory.md 的状态行数字 = 实测
    # 为什么要有它（2026-10-15 补）：同一轮里我把「提交数 / 入库数」写错过三次
    # （页面状态条 · memory 提交数 · memory 入库数）——全是"按加一写、没实测"。
    # 页面那三项目前由 E3 钉住，而 memory.md 的同类数字【此前无任何东西在查】。
    # memory.md 不存在时跳过（首次使用尚未初始化，AGENTS.md §5 同口径）。
    $memPath = Join-Path $RepoRoot 'memory.md'
    if (-not (Test-Path -LiteralPath $memPath)) {
        "  SKIP  E4：memory.md 不存在（尚未初始化）"
    } else {
        $memTxt = [System.IO.File]::ReadAllText($memPath)
        $memBad = @()
        $mHead = [regex]::Match($memTxt, 'HEAD \*\*`([0-9a-fA-F]{7,40})`\*\*')
        $mComm = [regex]::Match($memTxt, '\*\*(\d+)\*\* 个提交')
        $mFile = [regex]::Match($memTxt, '入库 \*\*(\d+)\*\* 文件')
        if (-not $mHead.Success) { $memBad += 'memory 状态行缺 HEAD' }
        elseif ($mHead.Groups[1].Value -ne $realHead) { $memBad += "memory HEAD=$($mHead.Groups[1].Value) 实测=$realHead" }
        if (-not $mComm.Success) { $memBad += 'memory 状态行缺 提交数' }
        elseif ([int]$mComm.Groups[1].Value -ne [int]$realComm) { $memBad += "memory 提交=$($mComm.Groups[1].Value) 实测=$realComm" }
        if (-not $mFile.Success) { $memBad += 'memory 状态行缺 入库数' }
        elseif ([int]$mFile.Groups[1].Value -ne [int]$realFile) { $memBad += "memory 入库=$($mFile.Groups[1].Value) 实测=$realFile" }
        Assert-Cell -Name 'E4 memory.md 状态行 HEAD/提交/入库 = 实测' -Expect '不一致 = 0' `
            -Actual ([pscustomobject]@{ Exit = $memBad.Count; Stdout = ($memBad -join '; ') }) -Predicate { $memBad.Count -eq 0 }
    }
    # --- E2 · 页面的「用户待办」条数与源文件一致
    # 源文件不入库、无判据盯着它 —— 改动它不会有任何东西响。本格就是那个"盯着它"的东西。
    $todoSrc = Join-Path $RepoRoot '我要做什么.txt'
    if (Test-Path -LiteralPath $todoSrc) {
        $srcIds = @()
        foreach ($l in [System.IO.File]::ReadAllLines($todoSrc)) {
            if ($l -match '^(\d+)、') { $srcIds += [int]$Matches[1] }
        }
        # 页面 ② 组表格：取 "id=todo" 到下一个 h2 之间的 <tr><td>NN</td>
        $a = $pageTxt.IndexOf('id="todo"')
        $b = if ($a -ge 0) { $pageTxt.IndexOf('<h2', $a + 1) } else { -1 }
        $todoPageIds = @()
        if ($a -ge 0 -and $b -gt $a) {
            $seg = $pageTxt.Substring($a, $b - $a)
            foreach ($m in [regex]::Matches($seg, '<tr><td>(?:<b>)?(\d+)(?:</b>)?</td>')) { $todoPageIds += [int]$m.Groups[1].Value }
        }
        $todoMissing = @($srcIds | Where-Object { $_ -notin $todoPageIds })
        Assert-Cell -Name "E2 页面待办覆盖源文件（源 $($srcIds.Count) 条 / 页 $($todoPageIds.Count) 条）" -Expect '漏条 = 0' `
            -Actual ([pscustomobject]@{ Exit = $todoMissing.Count; Stdout = ($todoMissing -join ',') }) -Predicate { $todoMissing.Count -eq 0 }
    } else {
        "  SKIP  E2：源文件 我要做什么.txt 不存在"
    }
}

# ================================================================ F · 角色只读围栏（GAP-001 残余）
# `tools:` 是声明，挂载才是事实 —— 但【声明本身】得先自洽，否则派发时才发现就晚了。
# 本组守一条【安全不变量】与它的对偶：
#   只读角色（description 标「只读」）= 机械只读 ⇒ tools 里【不得】有任何 shell
#   写方角色                        = 能干活   ⇒ tools 里【应有】一个 shell
# 两半都要，缺一半就会漏：
#   只查「只读不得有 shell」→ 漏掉「写方没声明 shell」⇒ 派去干活却发现干不了（GAP-001 的原形态）
#   只查「写方应有 shell」→ 漏掉「只读被加上 shell」⇒ 机械只读静默失效、无人报警
# 「完全没有 tools: 声明」= 退回默认工具集（可能含写权限）⇒ 对只读角色是同一族风险。
"== F · 角色只读围栏（GAP-001 残余）=="

$shellNames = 'PowerShell|Bash|cmd|zsh|fish|sh'
$agentDir = Join-Path $RepoRoot '.claude/agents'
$roViolations = @()   # 只读角色却带 shell（或完全没声明）
$rwViolations = @()   # 写方角色却没有 shell
$roCount = 0; $rwCount = 0

foreach ($f in @(Get-ChildItem -LiteralPath $agentDir -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($f.Name -eq 'README.md') { continue }   # 文档不是角色，无 frontmatter
    $txt = [System.IO.File]::ReadAllText($f.FullName)
    $descMatch = [regex]::Match($txt, '(?m)^description:\s*(.+)$')
    $toolsMatch = [regex]::Match($txt, '(?m)^tools:\s*(.+)$')
    $isReadOnly = $descMatch.Success -and $descMatch.Groups[1].Value -match '只读'
    $toolsLine = if ($toolsMatch.Success) { $toolsMatch.Groups[1].Value.Trim() } else { '' }
    $hasShell = $toolsLine -match $shellNames

    if ($isReadOnly) {
        $roCount++
        # 只读必须以『仅 Read / Grep / Glob』收口；带 shell 即破围栏；无声明同样不合格
        if ($toolsLine -eq '') { $roViolations += "$($f.Name) — 无 tools: 声明（退回默认工具集）" }
        elseif ($hasShell) { $roViolations += "$($f.Name) — 只读却带 shell：$toolsLine" }
        elseif ($toolsLine -match 'Write|Edit') { $roViolations += "$($f.Name) — 只读却带 Write/Edit：$toolsLine" }
    } else {
        $rwCount++
        if (-not $hasShell) { $rwViolations += "$($f.Name) — 写方却无 shell：$toolsLine" }
    }
}

Assert-Cell -Name "F1 只读角色不含 shell/Write/Edit 且有声明（$roCount 个只读角色）" -Expect '违规 = 0' `
    -Actual ([pscustomobject]@{ Exit = $roViolations.Count; Stdout = ($roViolations -join '; ') }) -Predicate { $roViolations.Count -eq 0 }

Assert-Cell -Name "F2 写方角色已声明 shell（$rwCount 个写方角色）" -Expect '违规 = 0' `
    -Actual ([pscustomobject]@{ Exit = $rwViolations.Count; Stdout = ($rwViolations -join '; ') }) -Predicate { $rwViolations.Count -eq 0 }


# --- C6 · 全仓「格数总数」陈述一致（2026-10-15 补；**口径经两次收窄**）
# 为什么要有它：格数被抄在 8 个文件里，**没有任何东西让它们同步** —— 同一轮里我因此错了 4 次。
#
# ⚠️ 第一版判据【是错的，如实记】：它扫全仓所有「NN 格」，于是把**合法数字**也报了 ——
# 规划总数（45）· 历史对比（「方案原文称 29 格」）· 时间线（「增至 19 格」）· 分组内数（「A 11」）。
# **误报的判据比没有判据更糟**：它会教人忽略它（D3：判据必须测它声称要测的东西）。
# 故【只认「总数」的固定说法】，不含历史/规划/分组：
$totalPatterns = @(
    '共\s*\*{0,2}(\d+)\s*\*{0,2}\s*格',        # 「共 33 格」
    '一键[：:\s]\s*\*{0,2}(\d+)\s*\*{0,2}\s*格', # 「一键：33 格」
    '\*{0,2}(\d+)\s*格\s*·\s*A–F',              # 「33 格 · A–F」
    '六组\s*/\s*\*{0,2}(\d+)\s*\*{0,2}\s*格',    # 「六组 / 33 格」
    'A–F,\s*\*{0,2}(\d+)\s*cells',              # 英文
    'PASS\s*=\s*(\d+)\s*/\s*FAIL'               # 「PASS = 33 / FAIL」
)
$foundTotals = @{}
foreach ($f in @(git -C $RepoRoot ls-files '*.md')) {
    # 排除 roadmap：它【合法地】含历史对比（『方案原文称 29 格』）与规划数（『三组共 13 格』）。
    # 一个判据若把合法输入也报出来，就是在教人忽略它（D3）。
    if ($f -like '*roadmap-production*') { continue }
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $txt = [System.IO.File]::ReadAllText($fp)
    foreach ($p in $totalPatterns) {
        foreach ($m in [regex]::Matches($txt, $p)) { $foundTotals[[int]$m.Groups[1].Value] = $true }
    }
}
$actualCells = $script:Pass + $script:Fail + 1   # +1 = C6 自己这一格（此刻尚未计入）
$staleTotals = @($foundTotals.Keys | Where-Object { $_ -ne $actualCells } | Sort-Object)
Assert-Cell -Name "C6 全仓格数【总数】陈述一致（实际 $actualCells；文中出现 $($foundTotals.Keys -join '/')）" `
    -Expect "非 $actualCells 的总数陈述 = 0" `
    -Actual ([pscustomobject]@{ Exit = $staleTotals.Count; Stdout = ($staleTotals -join ',') }) `
    -Predicate { $staleTotals.Count -eq 0 }

# ================================================================ 小结
""
"---- 小结 ----"
"  PASS = $script:Pass"
"  FAIL = $script:Fail"
""
if ($script:Fail -gt 0) {
    "守卫自测【未通过】——有格的读数与预期不符，守卫可能已失明。"
    "判据是【每一格的分支】，不是两个 SHA 的字面值。"
    exit 1
}
"守卫自测【全部通过】——两条守卫在最该报警的输入上都报了警，"
"且在最该静默的输入上都静默。silence 现在携带信息。"
exit 0
