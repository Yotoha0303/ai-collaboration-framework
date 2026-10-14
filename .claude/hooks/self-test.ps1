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

    # A4 —— GAP-025 的失明格
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b class=""v"">0000000</b></div></body></html>`n")
    $a4 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A4 负控 <b> 加 class 属性 → 静默（GAP-025 会瞎）' -Expect 'exit 0 且 stdout 空' -Actual $a4 `
        -Predicate { $a4.Exit -eq 0 -and $a4.Stdout -eq '' }
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
