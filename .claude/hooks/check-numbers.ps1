# Stop-hook guard: identifier numbers must not collide ACROSS BRANCHES.
#
# The number space of docs/changes/NNN-*.md is shared by the WHOLE repo, across
# ALL branches. Two parallel branches each pick the same number and the collision
# only surfaces at merge time. A guard that looks only at HEAD is a FALSE guard:
# it stays green while the numbers collide. Measured in the project this
# framework was built for: three files all numbered 022 on one branch, and two
# further cross-branch collisions in a single round - every one of them invisible
# to `git ls-files docs/changes/` (which sees only the current checkout).
#
# CRITERION (the whole point): union the CURRENT state of every branch and remote
# branch, then a number that names >=2 DISTINCT files is a collision. Not "does
# HEAD have a duplicate" - HEAD cannot, the filenames are distinct there.
#
# Exit 0 with no output   -> no collision, allow the turn to end.
# Exit 1 with stderr      -> a collision (or the guard could not run). NOTICE, not
#                            block: the colliding branch may be one the current
#                            session must not rewrite, so this informs rather than
#                            blocks. (exit 1 is the documented notice channel; see
#                            check-progress.ps1 for why not `systemMessage`.)
#
# Paths derive from the script's OWN location, never the working directory.
# A workspace with no orchestrated project (no child holding .git) is silent:
# there is no number space to check, which is "not initialised", not a fault.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

try {
    # <workspaceRoot>/.claude/hooks/check-numbers.ps1  ->  <workspaceRoot>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $claudeDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $claudeDir

    # Projects = EVERY child of the workspace holding a .git entry, not just the
    # first. A multi-project workspace is the normal case (measured: a workspace
    # with both `go-order-...` and `koliance` - picking the first, alphabetically,
    # silently watched the wrong repo and reported "clear" while a real collision
    # sat in the other). Each project is checked; a collision in ANY of them is
    # reported.
    $projects = @()
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $ws -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $projects += $d.FullName }
        }
    } catch { $projects = @() }
    if ($projects.Count -eq 0) { exit 0 }

    # git must be usable (functional probe, judged by exit code).
    $null = & git -C $projects[0] rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("编号守卫未运行：编排项目存在但 git 不可用。本轮未检查编号撞车。")
        exit 1
    }

    $collisions = New-Object System.Collections.Generic.List[string]
    foreach ($proj in $projects) {
        $refs = @(& git -C $proj for-each-ref --format='%(refname)' refs/heads refs/remotes 2>$null)
        if ($refs.Count -eq 0) { continue }

        # Union the CURRENT docs/changes/ listing of every branch (not history:
        # `git log --all --name-only` would include pre-rename names and false-positive).
        $byNum = @{}
        foreach ($r in $refs) {
            $files = @(& git -C $proj ls-tree -r --name-only $r -- docs/changes/ 2>$null)
            foreach ($f in $files) {
                $leaf = [System.IO.Path]::GetFileName($f)
                if ($leaf -match '^(\d{3})-') {
                    $num = $Matches[1]
                    if (-not $byNum.ContainsKey($num)) { $byNum[$num] = @{} }
                    $byNum[$num][$leaf] = $true
                }
            }
        }

        $name = Split-Path -Leaf $proj
        foreach ($num in ($byNum.Keys | Sort-Object)) {
            $leaves = @($byNum[$num].Keys | Sort-Object)
            if ($leaves.Count -gt 1) {
                $collisions.Add("  [$name] $num : " + ($leaves -join '  |  '))
            }
        }
    }
    if ($collisions.Count -eq 0) { exit 0 }

    $msg = "编号跨分支撞车（docs/changes/）：同一编号在多条分支上命名了不同文件——`n" +
           ($collisions -join "`n") +
           "`n编号空间是全仓、跨分支共享的；只查 HEAD 的守卫看不见它（AGENTS.md §6.1）。" +
           "`n选号请查全部分支并集，别只看当前检出。"
    [Console]::Error.WriteLine($msg)
    exit 1
}
catch {
    # Never let the guard itself break a turn.
    exit 0
}
