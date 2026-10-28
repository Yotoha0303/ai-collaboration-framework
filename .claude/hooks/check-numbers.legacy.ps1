# Stop-hook guard: identifier numbers must not collide ACROSS BRANCHES.
#
# The number space of an adopter's `docs/changes/NNN-*.md` is shared by the WHOLE
# repo, across ALL branches. Two parallel branches each pick the same number and
# the collision only surfaces at merge time. A guard that looks only at HEAD is a
# FALSE guard: it stays green while the numbers collide. Measured in a real
# project this framework was built for: three files all numbered 022 on one
# branch, and two further cross-branch collisions in a single round - every one
# of them invisible to `git ls-files docs/changes/` (which sees only the current
# checkout).
#
# CRITERION (the whole point): union the CURRENT state of every branch and remote
# branch, then a number that names >=2 DISTINCT files is a collision. Not "does
# HEAD have a duplicate" - HEAD cannot, the filenames are distinct there.
#
# Exit 0 with no output   -> no collision, allow the turn to end.
# Exit 1 with stderr      -> a collision, OR the guard could not run (git
#                            unusable, exit code untrustworthy). NOTICE, not
#                            block: the colliding branch may be one the current
#                            session must not rewrite, so this informs rather
#                            than blocks. (exit 1 is the documented notice
#                            channel; see check-progress.ps1 for why not
#                            `systemMessage`.)
#
# Paths derive from the script's OWN location, never the working directory.
# Candidates are the workspace root ITSELF (self-hosted layout) plus every child
# holding `.git` (target / carrying layout). No candidate at all is silent: there
# is no number space to check, which is "not initialised", not a fault.
#
# THE ONE RULE (same as check-progress.ps1): every git call goes through
# `Invoke-GitChecked`, and the EXIT CODE is the only criterion -- output is a
# PAYLOAD only and is NEVER the criterion. A positive probe plus a NEGATIVE
# CANARY force the binary to disagree across two inputs; without the canary, "the
# exit code means something" is an assumption, not a criterion.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Invoke-GitChecked {
    param([scriptblock]$GitCall)
    $script:__gitExit = $null
    $out = $null
    try {
        # Scoped EAP: a native command's non-zero exit writes stderr, and the
        # outer `Stop` would promote that to a terminating error which the outer
        # catch swallows into silence. This scoped EAP covers THAT case only -- it
        # does NOT cover "command not found" (CommandNotFoundException), which is
        # a statement-terminating error and is handled by the catch below.
        $out = & {
            $ErrorActionPreference = 'Continue'
            # GAP-013①: an ambient `GIT_DIR` HIJACKS every `git -C <repo>` below.
            # `-C` picks the working directory, but `GIT_DIR` overrides repository
            # discovery entirely -- so the guard would read ANOTHER repo's HEAD.
            # Measured: with `GIT_DIR` pointing at a repo whose HEAD happened to
            # match the page, the guard exits 0 SILENTLY and waves a stale page
            # through. This guard resolves its own target explicitly, so an
            # ambient GIT_DIR must not override it.
            # ($env: is PROCESS-scoped, not scope-scoped -- hence save/restore.)
            $savedGitDir = $env:GIT_DIR
            $env:GIT_DIR = $null
            try {
                & $GitCall
                $script:__gitExit = $LASTEXITCODE
            } finally {
                $env:GIT_DIR = $savedGitDir
            }
        }
    } catch {
        # A git that cannot even be launched lands here: CommandNotFoundException
        # (git not on PATH), or the ApplicationFailedException of a zero-byte /
        # truncated git.exe. Leaving Exit as $null keeps `.Exit -eq 0` false --
        # fail closed, never silent.
        $script:__gitExit = $null
        $out = $null
    }
    return [pscustomobject]@{ Exit = $script:__gitExit; Text = [string]::Join("`n", @($out)).Trim() }
}

function Write-Notice([string]$Text) {
    # One channel for every "guard could not run" branch, so they stay same-shaped
    # (D4: two facts of different maturity must not coexist).
    [Console]::Error.WriteLine("编号守卫未运行：" + $Text + "本轮未检查编号撞车。")
}

try {
    # <workspaceRoot>/.claude/hooks/check-numbers.ps1  ->  <workspaceRoot>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $claudeDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $claudeDir

    # Candidates = the workspace root ITSELF, plus EVERY child holding a `.git`
    # entry. The root itself matters: under the self-hosted layout the repo IS the
    # workspace root, and a child-only scan would find zero projects and silently
    # pass. Children matter under the target and carrying layouts.
    $projects = @()
    if (Test-Path -LiteralPath (Join-Path $ws '.git')) { $projects += $ws }
    try {
        # `-ErrorAction Stop` is deliberate: a FAILED enumeration is not the same
        # fact as "there are no candidates", and collapsing the two is how a
        # permission error becomes a silent pass (GAP-020's second half).
        foreach ($d in @(Get-ChildItem -LiteralPath $ws -Directory -Force -ErrorAction Stop)) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $projects += $d.FullName }
        }
    } catch {
        Write-Notice "无法枚举工作区目录（枚举失败 ≠ 没有候选仓）。"
        exit 1
    }
    # Only NOW is "no candidates" a fact rather than a failure to look.
    #
    # No candidates => silent exit, DELIBERATELY, even if git is unusable. This
    # guard's subject is the identifier space inside adopter repos; a workspace
    # with no repo at all is "not initialised", and AGENTS.md §5 requires that
    # state to be silent (same convention as the progress-page guard). The
    # instrument checks below therefore sit AFTER this exit, not before it — they
    # test git, which is only relevant once there is something to measure.
    # (Ruling: this ordering was briefly the other way; see ledger GAP-020.)
    if ($projects.Count -eq 0) { exit 0 }

    # Probe FUNCTIONALLY and BY EXIT CODE (never by the truthiness of output):
    # `Get-Command git` only proves the name RESOLVES, and a zero-byte git.exe on
    # PATH passes it then fails at call time. `Invoke-GitChecked` leaves `.Exit`
    # $null when git cannot be launched, and `$null -eq 0` is false, so both
    # failure shapes land on this branch.
    if ((Invoke-GitChecked { git --version 2>$null }).Exit -ne 0) {
        Write-Notice "PATH 上的 git 不可用（缺失或无法执行）。"
        exit 1
    }

    # NEGATIVE CANARY (the dual of the probe above). The probe demands "this MUST
    # SUCCEED"; the canary demands "this MUST FAIL". Together they force the binary
    # to return DIFFERENT exit codes for two different inputs, which is what makes
    # the exit code trustworthy rather than merely assumed: a shim that always
    # exits 0 passes the probe and is caught here; a shim that always exits
    # non-zero is caught by the probe. The input is an all-zero object id, which
    # names no object in any repo, so `--verify` must fail.
    if ((Invoke-GitChecked { git rev-parse --verify --quiet "0000000000000000000000000000000000000000^{commit}" 2>$null }).Exit -eq 0) {
        Write-Notice "PATH 上的 git 退出码不可信（对必定失败的输入仍返回 0）。"
        exit 1
    }

    $collisions = New-Object System.Collections.Generic.List[string]
    foreach ($proj in $projects) {
        $probe = Invoke-GitChecked { git -C $proj rev-parse --git-dir 2>$null }
        if ($probe.Exit -ne 0) {
            Write-Notice ("候选仓库不可用（" + (Split-Path -Leaf $proj) + "）。")
            exit 1
        }

        $refsCall = Invoke-GitChecked { git -C $proj for-each-ref --format='%(refname)' refs/heads refs/remotes 2>$null }
        if ($refsCall.Exit -ne 0) {
            Write-Notice ("无法枚举分支（" + (Split-Path -Leaf $proj) + "）。")
            exit 1
        }
        $refs = @($refsCall.Text -split "`n" | Where-Object { $_ -ne '' })
        if ($refs.Count -eq 0) { continue }

        # COLLAPSE local refs with their remote-tracking counterparts (measured
        # 2026-10-26): `refs/heads/X` and `refs/remotes/origin/X` are the SAME
        # branch, but they hold DIFFERENT oids whenever a local commit has not
        # been pushed yet -- which is the normal state during any feature
        # branch's development. Unioning both raw ref sets therefore reports
        # `docs/changes/001-*.md` against itself as a "cross-branch collision"
        # on every unpushed commit: a guard that fires during normal work is a
        # guard people learn to ignore (D3).
        # Rule: key by BRANCH LEAF NAME; a local ref shadows the remote-tracking
        # ref of the same name. Different branch names still compare against
        # each other -- that is the collision this guard exists to catch.
        # `refs/remotes/<remote>/HEAD` is a symbolic alias, not a branch: skip it.
        # The dictionary is Ordinal (case-SENSITIVE) for the same reason the
        # collision container below is: branch names differing only in case are
        # two branches on a case-sensitive filesystem.
        $byLeaf = New-Object 'System.Collections.Generic.Dictionary[string, string]' ([System.StringComparer]::Ordinal)
        # Local refs first, so they win the "first occurrence" race.
        foreach ($r in @($refs | Sort-Object { if ($_ -like 'refs/heads/*') { 0 } else { 1 } })) {
            $leaf = ($r -replace '^refs/heads/', '') -replace '^refs/remotes/[^/]+/', ''
            if ($leaf -eq 'HEAD') { continue }
            if (-not $byLeaf.ContainsKey($leaf)) { $byLeaf[$leaf] = $r }
        }
        $refs = @($byLeaf.Values)
        if ($refs.Count -eq 0) { continue }

        # Union the CURRENT docs/changes/ listing of every branch (not history:
        # `git log --all --name-only` would include pre-rename names and false-positive).
        #
        # CRITERION: a number is a collision when it names MORE THAN ONE DISTINCT
        # (path, blob oid) pair. That is the header's ">=2 DISTINCT files" read
        # literally, and it is deliberately wider than ">=2 distinct leaf names":
        #   - two branches each evolving their own `NNN-fix.md` (same path, different
        #     oid) is an add/add conflict at merge time -> a collision (human ruling,
        #     ledger GAP-019);
        #   - two paths that merely share content are still two distinct files;
        #   - the SAME (path, oid) seen on several branches is one file -> not a
        #     collision.
        #
        # The container is CASE-SENSITIVE (Ordinal), not PowerShell's literal `@{}`.
        # `@{}` compares keys case-INSENSITIVELY, so `NNN-Alpha.md` and `NNN-alpha.md`
        # collapsed into ONE key and a real cross-branch collision read as clear
        # (measured, pre-existing). Pinning the comparer keeps the two distinct.
        #
        # `-z` gives NUL-separated records with unquoted paths, so a path containing
        # spaces or quotes cannot silently break the parse.
        $byNum = New-Object 'System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]'
        foreach ($r in $refs) {
            $tree = Invoke-GitChecked { git -C $proj ls-tree -r -z $r -- docs/changes/ 2>$null }
            if ($tree.Exit -ne 0) {
                Write-Notice ("无法列出分支树（" + (Split-Path -Leaf $proj) + " / " + $r + "）。")
                exit 1
            }
            foreach ($rec in @($tree.Text -split "`0" | Where-Object { $_ -ne '' })) {
                # <mode> SP <type> SP <oid> TAB <path>
                if ($rec -match '^\S+\s+\S+\s+(?<oid>[0-9a-f]+)\t(?<path>.+)$') {
                    $oid = $Matches['oid']
                    $relPath = $Matches['path']
                    # The NUMBER is taken from the leaf; the IDENTITY is the FULL path.
                    # Keying identity by the leaf alone would merge `NNN-a.md` with
                    # `old/NNN-a.md` — two distinct files under one number (measured).
                    $leaf = [System.IO.Path]::GetFileName($relPath)
                    if ($leaf -match '^(\d{3})-') {
                        $num = $Matches[1]
                        if (-not $byNum.ContainsKey($num)) {
                            $byNum[$num] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                        }
                        # `$null =` is load-bearing: HashSet.Add returns bool, and a
                        # bare call would print `True` to stdout on every new entry,
                        # breaking the "exit 0 with no output" contract.
                        $null = $byNum[$num].Add($relPath + '@' + $oid)
                    }
                }
            }
        }

        $name = Split-Path -Leaf $proj
        foreach ($num in @($byNum.Keys | Sort-Object)) {
            $seen = @($byNum[$num] | Sort-Object)
            if ($seen.Count -gt 1) {
                # Split on the LAST '@': the oid is trailing hex and can never contain
                # one, while a PATH can (it is a legal filename character). Splitting on
                # the first '@' would mis-parse such a path, and the short-oid slice
                # would then throw — swallowing the collision report behind a
                # "the guard itself errored" notice (measured).
                $shown = @($seen | ForEach-Object {
                    $i = $_.LastIndexOf('@')
                    $p = $_.Substring(0, $i)
                    $o = $_.Substring($i + 1)
                    $p + ' (' + $o.Substring(0, [Math]::Min(7, $o.Length)) + ')'
                })
                $collisions.Add("  [$name] $num : " + ($shown -join '  |  '))
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
    # A guard that dies silently is indistinguishable from a guard that is happy
    # (GAP-015's whole family). Report instead: `exit 1` is the documented
    # NON-blocking notice channel, so this informs without breaking the turn.
    #
    # Carry the EXCEPTION TEXT, not just a fixed phrase: a bare "the guard itself
    # errored" reads identically to "git unusable" / "exit code untrustworthy" /
    # "candidate repo unusable" / "cannot enumerate refs" / "cannot list branch
    # tree" — five different causes, one indistinguishable message (measured).
    # Keep it to the first line so the notice stays a notice.
    $why = ''
    if ($null -ne $_.Exception -and $null -ne $_.Exception.Message) {
        # FIRST LINE only — the comment below means it: a multi-line Message would
        # flood stderr and stop reading as a notice.
        $why = ($_.Exception.Message -split "`r?`n")[0]
    }
    $line = ''
    if ($null -ne $_.InvocationInfo -and $null -ne $_.InvocationInfo.ScriptLineNumber) { $line = ' @' + $_.InvocationInfo.ScriptLineNumber }
    Write-Notice ("守卫自身出错" + $line + "：" + $why)
    exit 1
}
