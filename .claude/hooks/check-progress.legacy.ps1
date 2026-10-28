# Stop-hook guard: the progress page must not lag the MAINLINE.
#
# The page carries the HEAD it was built from in its status bar
# (`<div>head <b>…</b></div>`). If that no longer matches the MAINLINE, the
# page describes a state that no longer exists — the "two facts at different
# maturities" problem the project's own discipline (D4) forbids, sitting outside
# the repo where the ledger cannot catch it.
#
# Which commit is "the mainline"? GAP-031: NOT the checked-out HEAD. A progress
# page is a stakeholder-facing fact about the trunk; on any feature branch the
# checked-out HEAD is a private, short-lived fact. Comparing against HEAD made
# the guard cry "lagging" on every branch whose tip differed from the page's
# (correct) mainline SHA — measured twice in a real workspace, and reproducible
# with NO commit on the new branch at all, as soon as the trunk moves on.
# The three-level resolution (remote default branch -> local main -> HEAD as an
# explicit fallback) is documented where it is implemented, further down.
#
# Exit 0 with no output -> allow the turn to end.
# Exit 0 with JSON      -> `decision:block` feeds the reason back to the model,
#                          which must update the page before stopping.
#                          This guard emits `decision:block` for a lagging page.
# Exit 1 with stderr    -> a NON-BLOCKING error the user actually sees: git
#                          unusable, or a pointer that exists but yields no page
#                          name. (`systemMessage` is documented but shows only in
#                          the Ctrl+O transcript on this setup, not the terminal —
#                          measured: the user reported not seeing it, so both
#                          notice-only branches use exit 1 + stderr instead.)
#
# THE ONE RULE THIS FILE FOLLOWS (read this before editing any git call):
# every git call whose result decides anything is judged by its EXIT CODE == 0.
# Output is a PAYLOAD only and is NEVER the criterion. Three separate silent
# failures were measured from breaking that rule — one family, not three bugs:
#   - `Get-Command git` proves only that the NAME RESOLVES. A zero-byte git.exe
#     on PATH passes it and throws ApplicationFailedException at call time.
#   - taking the TRUTHINESS OF THE OUTPUT instead of the exit code: a shim that
#     prints nothing and exits 0 was read as "git unusable" (false alarm).
#   - comparing the OUTPUTS of `rev-parse HEAD` and `rev-parse --verify` as
#     STRINGS: a shim that always exits 128 while printing a constant made both
#     sides equal garbage -> judged "in sync" -> silent exit 0.
# Patching those one at a time kept missing the next one, so the rule is
# structural: ALL git calls go through `Invoke-GitChecked`, which is the ONLY
# place a git exit code is read. `.Exit` is the criterion; `.Text` is payload.
#
# Why PowerShell and not bash: if Git for Windows lives somewhere that keeps
# `usr\bin` off the Windows PATH, a hook command of
# `bash ...` fails with "not recognized". System32 is always on PATH, so
# `powershell` resolves. The script also derives every path from its own
# location rather than from CLAUDE_PROJECT_DIR, so it works regardless of how
# the hook is invoked or what the working directory is.
#
# Layout this script assumes. THIS repository is self-hosted: the workspace root
# IS the repo, so the framework files sit in the repo by design (GAP-004: the
# "framework cannot enter the repo" argument does not hold in this layout).
#
#     <workspaceRoot>/                     <- session working directory == this repo
#         CLAUDE.md                        <- thin entry point (imports AGENTS.md)
#         .claude/hooks/check-progress.ps1 <- this file
#         .claude/progress-page.txt        <- ONE line: the page's file name
#         <page>                           <- the page, sibling of .claude/
#         project/                         <- repo (contains .git) in the TARGET layout
#
# Both layouts are still supported: the workspace root always wins if it holds
# `.git`, and the repo may equally be a `project/` child.
#
# The page NAME is read from `.claude/progress-page.txt`, not hardcoded: the page
# is renamed as the project progresses, and a rename must not require editing
# this script (or silently kill the guard).
#
# Both lookups below resolve from the script's OWN location, never from the
# working directory — the hook may run with any CWD.
#
# Silent cases on purpose: no git HEAD, no HEAD marker in the page (the page was
# restructured beyond recognition; a false alarm on every stop is worse than
# saying nothing), and NO page at all. GAP-031 adds one more of the same kind:
# no MAINLINE can be resolved at all (no `origin/HEAD`, no local `main`, and no
# commit on HEAD either) — same unborn landing as GAP-012.
#
# A MISSING page is silent by human decision (AGENTS.md section 5, "initialise on
# first use, no report needed"): the premise is "the page EXISTS and must not
# lag". With no page there is no fact to compare — it means "not initialised
# yet", NOT "the page was lost". Alerting here is pure noise on a fresh
# workspace.
#
# NOTE: these lookups fail closed by design, so a WRONG path derivation makes
# this guard silently never block. That is OBSERVATIONALLY EQUIVALENT to the
# missing-page case, so verifying "silent when absent" proves nothing at all.
# If the layout or the page name ever changes, re-verify with BOTH cases:
#   (a) no page         -> silent exit 0
#   (b) stale SHA in an existing page -> must emit decision:block
# Only (b) has teeth; if (b) still blocks, (a)'s silence can be trusted as
# "no criterion applies" rather than "the script is dead".

$ErrorActionPreference = 'Stop'

# UTF-8 for BOTH channels, and it must happen BEFORE either is written: the
# notice-only branches write Chinese to stderr and the block path writes Chinese
# to stdout, so one shared setting covers both (D4: two branches, one form).
# Wrapped in try/catch on purpose — this setter throws on a host that cannot
# change the console encoding, and an unguarded throw here would kill the guard
# (measured: the A7-f2 case, where an unguarded setter turned the BLOCK path
# silent). Measured under chcp 936: with this line the stderr Chinese is valid
# UTF-8 and readable; without it the same bytes come out as GBK mojibake, or as
# '?' on code pages that cannot represent the characters at all.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# The ONLY place a git exit code is read. Everything that decides something
# calls this and tests `.Exit -eq 0`.
#
# GAP-031 widened what is cleared here: `GIT_DIR` alone was enough while every
# call was `rev-parse --short HEAD` / `rev-parse HEAD`. The mainline resolution
# added `rev-parse --verify <ref>^{commit}`, and THAT is hijackable by
# `GIT_OBJECT_DIRECTORY` / `GIT_COMMON_DIR`: with either pointing at another
# repo, the walk to the commit fails (exit 1) and the guard falls silent —
# measured (2026-10-17) as a REGRESSION of cell A11, which is exactly what that
# cell exists to catch. The width was chosen by measurement, not by enumeration:
# on this git (2.49.0.windows.1) exactly those two variables changed the reading.
# The other seven are cleared anyway — clearing costs nothing and "which one
# hijacks" is a git implementation detail nobody should have to remember.
#
# `$script:` is deliberate, and it is measured rather than assumed: a scriptblock
# invoked with `& { }` runs in a CHILD scope that can READ the enclosing script
# scope but whose unqualified assignments land in that child scope and are lost.
# Writing `$script:__gitExit` is what carries the code back out. (Measured on
# this machine, Windows PowerShell 5.1.19041.6456 + git 2.49.0.windows.1:
# `$LASTEXITCODE` itself does survive a plain `& { }` into the parent scope, but
# NOT through an assignment that would otherwise be scoped to the child, so the
# explicit `$script:` write is what makes the helper immune to the difference.)
$GitEnvFamily = @(
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_COMMON_DIR',
    'GIT_INDEX_FILE',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_CEILING_DIRECTORIES',
    'GIT_NAMESPACE',
    'GIT_PREFIX'
)
function Invoke-GitChecked {
    param([scriptblock]$GitCall)
    $script:__gitExit = $null
    $out = $null
    try {
        # Scoped EAP: a native command's non-zero exit writes stderr, and the
        # outer `Stop` would promote that to a terminating error which the outer
        # catch swallows into silence. This scoped EAP covers THAT case only — it
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
            # GAP-031: clear the WHOLE family, not just GIT_DIR (see the note above).
            # ($env: is PROCESS-scoped, not scope-scoped -- hence save/restore.)
            $saved = @{}
            foreach ($n in $GitEnvFamily) {
                $saved[$n] = [Environment]::GetEnvironmentVariable($n)
                [Environment]::SetEnvironmentVariable($n, $null)
            }
            try {
                & $GitCall
                $script:__gitExit = $LASTEXITCODE
            } finally {
                foreach ($n in $GitEnvFamily) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
            }
        }
    } catch {
        # A git that cannot even be launched lands here: CommandNotFoundException
        # (git not on PATH), or the ApplicationFailedException of a zero-byte /
        # truncated git.exe. Leaving Exit as $null keeps `.Exit -eq 0` false —
        # fail closed, never silent.
        $script:__gitExit = $null
        $out = $null
    }
    return [pscustomobject]@{ Exit = $script:__gitExit; Text = [string]::Join("`n", @($out)).Trim() }
}

try {
    # <workspaceRoot>/.claude/hooks/check-progress.ps1  ->  <workspaceRoot>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $claudeDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $claudeDir

    # Page NAME comes from a one-line pointer file so the page can be renamed
    # without touching this script. The pointer is the page name's single source
    # of truth, so a pointer that EXISTS but yields NO name (empty, whitespace,
    # or unreadable) is a real fault: this script would otherwise silently keep
    # using the stale default name below. That case is reported to the user via
    # exit 1 + stderr (the notice-only channel; see the header). A pointer naming
    # a page that does NOT exist stays silent —
    # an ACCEPTED COST (AGENTS.md section 5): that is observationally identical
    # to "not initialised yet", which must not alert. A pointer file that is
    # absent altogether is likewise "not initialised yet", not a fault.
    $name = 'project-progress.html'
    $pointerFault = $false
    $nameFile = Join-Path $claudeDir 'progress-page.txt'
    if (Test-Path -LiteralPath $nameFile) {
        $fromFile = Get-Content -LiteralPath $nameFile -Raw -ErrorAction SilentlyContinue
        if ($fromFile -and $fromFile.Trim()) { $name = $fromFile.Trim() }
        else { $pointerFault = $true }
    }

    # The page is the sibling of `.claude/` in the current layout; in the
    # pre-move layout (`.claude/` inside the repo) it is the sibling of the repo.
    # Trying both keeps the guard alive across a revert of the move — a guard
    # that fails closed must not go quietly dead when the layout shifts.
    $page = @((Join-Path $ws $name),
              (Join-Path (Split-Path -Parent $ws) $name)) |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

    # The pointer EXISTED but named nothing: the page lookup above fell back to
    # the default name, so the guard may be watching the wrong file entirely.
    # That is a real fault, not "not initialised yet" — report it to the user.
    # It takes precedence over the silent no-page case below: with no usable page
    # name the guard cannot even tell WHICH page is missing. (The lookup itself
    # proved the pointer file exists, so no second test is needed here.) The
    # silent fallback this replaces is the GAP-002 defect.
    if ($pointerFault) {
        [Console]::Error.WriteLine("进度页指针异常：.claude/progress-page.txt 存在但读不出页名（空 / 全空白 / 不可读）。守卫已回退到默认页名，可能在看一个错误的文件。")
        exit 1
    }

    # No page -> nothing to compare against, so there is no criterion to apply.
    # The premise is "the page exists and must not lag"; a page that was never
    # created cannot lag. "Not initialised yet" != "the page went missing" —
    # so exit silently (human decision; see AGENTS.md section 5).
    if (-not $page) { exit 0 }

    # git unusable -> the notice-only channel (exit 1 + stderr), NOT silence and
    # NOT `decision:block`. Missing git means the guard CANNOT TELL whether the
    # page lags, so blocking every turn would make the framework unusable; and
    # the failure must be visible, which is why it is not silent.
    #
    # Probe FUNCTIONALLY and BY EXIT CODE: `Get-Command git` only proves the name
    # RESOLVES — a zero-byte or truncated git.exe on PATH passes it and then
    # fails at call time (GAP-013-2), and judging the probe by the truthiness of
    # its OUTPUT misreads a silent-but-working git as broken. `Invoke-GitChecked`
    # returns $null for `.Exit` when the command cannot be launched at all, and
    # `$null -eq 0` is false, so both failure shapes land on the same branch.
    $gitOk = ((Invoke-GitChecked { git --version 2>$null }).Exit -eq 0)
    if (-not $gitOk) {
        [Console]::Error.WriteLine("进度页守卫未运行：PATH 上的 git 不可用（缺失或无法执行）。本轮未检查进度页是否落后。")
        exit 1
    }

    # NEGATIVE CANARY (the dual of the probe above). The probe demands "this MUST
    # SUCCEED"; the canary demands "this MUST FAIL". Together they force the
    # binary to return DIFFERENT exit codes for two different inputs, which is
    # what makes the exit code trustworthy rather than merely assumed: a shim
    # that always exits 0 passes the probe and is caught here; a shim that always
    # exits non-zero is caught by the probe. A positive probe alone leaves "the
    # exit code means something" as an ASSUMPTION -- with the canary it becomes a
    # CRITERION.
    #
    # The input is an all-zero object id, which names no object in any repo, so
    # `--verify` must fail. Same shape as every other git call here: it goes
    # through `Invoke-GitChecked`, the single place an exit code is read, and it
    # is judged by `.Exit` alone.
    $canary = Invoke-GitChecked { git rev-parse --verify --quiet "0000000000000000000000000000000000000000^{commit}" 2>$null }
    if ($canary.Exit -eq 0) {
        [Console]::Error.WriteLine("进度页守卫未运行：PATH 上的 git 退出码不可信（对必定失败的输入仍返回 0）。本轮未检查进度页是否落后。")
        exit 1
    }

    # The repo is the directory holding `.git`. Both layouts are supported: the
    # workspace root itself (self-hosted, the usual case here) and a `project/`
    # child (target layout).
    # ORDER MATTERS -- workspace root FIRST. A `project/` directory that merely
    # EXISTS is not a repo; if it were tried first and someone later ran
    # `git init` inside it, this guard would lock onto that inner, EMPTY repo,
    # find no HEAD, and go permanently silent -- which is exactly what it looks
    # like when it works. Both candidates stay: a fail-closed guard must not go
    # quietly dead when the layout shifts.
    #
    # A candidate must RESOLVE as a git repo, not merely hold a `.git` entry
    # (GAP-009) — and "resolve" means the call EXITS 0, judged by exit code like
    # every other git call here (a non-zero exit used to be swallowed into
    # silence by the outer `Stop` + catch; the helper's scoped EAP is what keeps
    # git's stderr off that outer catch).
    $repo = $null
    foreach ($cand in @($ws, (Join-Path $ws 'project'))) {
        if (-not (Test-Path -LiteralPath (Join-Path $cand '.git'))) { continue }
        if ((Invoke-GitChecked { git -C $cand rev-parse --git-dir 2>$null }).Exit -eq 0) { $repo = $cand; break }
    }
    if (-not $repo) { exit 0 }

    # --- GAP-031: the criterion is the MAINLINE, not the checked-out HEAD.
    #
    # Resolved in three levels; the FIRST one that holds wins:
    #   1. the remote default branch (`symbolic-ref refs/remotes/origin/HEAD`,
    #      e.g. `refs/remotes/origin/main`). `symbolic-ref` alone is NOT enough:
    #      it does not resolve unborn / dangling targets, so the result must then
    #      pass `rev-parse --verify` (exit code 0). BOTH steps are judged by exit
    #      code, never by the truthiness of the output.
    #   2. the local trunk branch `refs/heads/main` (`rev-parse --verify` exit 0).
    #   3. the checked-out HEAD — the previous behaviour, kept as an EXPLICIT
    #      fallback. A repo with neither `origin/HEAD` nor `main` (a fresh
    #      `git init`, no remote) has no "mainline" concept at all: erroring out
    #      here would put noise exactly at onboarding time (the same judgement
    #      GAP-012 recorded for unborn repos), and exiting silently would make
    #      the guard look like it runs. So HEAD it is — but the reason string
    #      always NAMES the line that was used, so a reader can tell which one.
    #
    # WHY this ordering matters (measured, issue #36): on a feature branch the
    # checked-out HEAD is NOT the trunk. A page recording the trunk's (correct)
    # SHA was reported as "lagging" — twice in a real workspace — and the same
    # false alarm reproduces on a brand-new branch with NO commit of its own.
    $mainRef = $null
    $mainName = $null
    $originHead = Invoke-GitChecked { git -C $repo symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null }
    if ($originHead.Exit -eq 0 -and $originHead.Text) {
        $candRef = $originHead.Text
        if ((Invoke-GitChecked { git -C $repo rev-parse --verify --quiet "$candRef^{commit}" 2>$null }).Exit -eq 0) {
            $mainRef = $candRef
            $mainName = $candRef -replace '^refs/remotes/', ''     # refs/remotes/origin/main -> origin/main
        }
    }
    if (-not $mainRef) {
        if ((Invoke-GitChecked { git -C $repo rev-parse --verify --quiet 'refs/heads/main^{commit}' 2>$null }).Exit -eq 0) {
            $mainRef = 'refs/heads/main'
            $mainName = 'main'
        }
    }
    if (-not $mainRef) {
        if ((Invoke-GitChecked { git -C $repo rev-parse --verify --quiet 'HEAD^{commit}' 2>$null }).Exit -eq 0) {
            $mainRef = 'HEAD'
            $mainName = 'HEAD（未找到主干）'
        }
    }

    # Nothing resolves (unborn repo, or a repo whose HEAD cannot be read): silent,
    # exactly as before — "the page exists and must not lag" has no premise here
    # (GAP-012; kept as-is, not claimed to be closed).
    if (-not $mainRef) { exit 0 }

    # FULL commit id of the mainline: this is the left-hand side of the compare.
    # Judged by exit code; `.Text` is the payload. The short form is fetched
    # separately for the error message only — it is never the criterion.
    $headFullProbe = Invoke-GitChecked { git -C $repo rev-parse --verify --quiet "$mainRef^{commit}" 2>$null }
    if ($headFullProbe.Exit -ne 0) { exit 0 }
    $headFull = $headFullProbe.Text
    if (-not $headFull) { exit 0 }
    $headShort = (Invoke-GitChecked { git -C $repo rev-parse --short $mainRef 2>$null }).Text
    if (-not $headShort) { $headShort = $headFull }

    $content = Get-Content -LiteralPath $page -Raw
    # Case-insensitive: an uppercase SHA must still be COMPARED, not fall through
    # to the "no HEAD marker" silence (GAP-008).
    #
    # GAP-025 partial fix: the regex previously required the LITERAL
    # `<div>head <b>SHA</b></div>`. ANY presentation change — adding a class
    # attribute, an id, a style — made it fail to match, and a failed match takes
    # the SILENT branch above. Measured: `head <b>deadbee</b>` blocks correctly,
    # while `head <b class="v">deadbee</b>` exits 0 with NO output, i.e. a stale
    # page is waved through. The guard goes blind rather than loud.
    #
    # So tolerate attributes on <div>, <b> and <i>, and whitespace around the SHA.
    # This does NOT remove the coupling — the marker is still a presentation
    # element, and a restructure into <span> would still blind it. It removes the
    # CHEAPEST way to go blind, which is the one a styling tweak hits by accident.
    #
    # Considered and REJECTED: writing the SHA a second time into a machine-readable
    # HTML comment and reading THAT. It would make the guard robust, but it creates
    # two copies of one fact (the visible `head` and the comment), and per D4 two
    # copies guarantee one goes stale first — with the guard then enforcing the
    # STALE one. The real fix is not a second copy but a guard that does not parse
    # presentation at all (e.g. content declared in front matter); that is a bigger
    # change and is NOT done here. Residual stays OPEN and registered as GAP-025.
    $m = [regex]::Match($content, '<div[^>]*>\s*head\s*<b[^>]*>\s*([0-9a-fA-F]{7,40})\s*</b[^>]*>\s*</div[^>]*>')
    if (-not $m.Success) { exit 0 }

    $recorded = $m.Groups[1].Value
    # Resolve both sides to FULL commit ids and compare those (GAP-008): any two
    # spellings naming the same commit match, while a fake SHA fails to resolve
    # and is correctly reported as lagging. `--quiet` keeps git's stderr quiet,
    # and the helper's scoped EAP keeps a failed `--verify` (e.g. the id names a
    # tree, not a commit) from being promoted to a terminating error that the
    # outer catch would swallow into silence. `ToLower()` because object ids are
    # lowercase hex. `$headShort` stays short -- error-message wording.
    #
    # BOTH SIDES ARE JUDGED BY EXIT CODE, and the outputs are compared only as
    # payload: comparing the two OUTPUTS as strings was itself a silent path —
    # a shim that always exits 128 while printing a constant made both sides
    # equal garbage and the guard called it "in sync" (the V13 case). A non-zero
    # exit on either side means the id did not resolve, which is a LAGGING page,
    # not a reason to fall silent.
    #
    # GAP-031: the left side is now the MAINLINE's full id ($headFull), resolved
    # above. The right side is unchanged on purpose (GAP-008's fix).
    $recFullProbe = Invoke-GitChecked { git -C $repo rev-parse --verify --quiet "$($recorded.ToLower())^{commit}" 2>$null }
    if (($recFullProbe.Exit -eq 0) -and ($headFull -eq $recFullProbe.Text)) { exit 0 }

    # The reason MUST name the line that was compared (GAP-031). The old wording
    # said "currently X", which on a feature branch points the reader at the
    # wrong fact — the page is stale relative to the TRUNK, not relative to their
    # branch tip.
    $reason = "进度页落后于主干：$name 记录的 HEAD 是 $recorded，而 $mainName 是 $headShort。" +
              "请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。" +
              "需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"

    [ordered]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
}
catch {
    # Never let the guard itself break a turn.
    exit 0
}
