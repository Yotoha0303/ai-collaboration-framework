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
