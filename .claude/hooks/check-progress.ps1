# Stop-hook guard: the progress page must not lag the repository.
#
# The page carries the HEAD it was built from in its status bar
# (`<div>head <b>…</b></div>`). If that no longer matches the repo's HEAD, the
# page describes a state that no longer exists — the "two facts at different
# maturities" problem the project's own discipline (D4) forbids, sitting outside
# the repo where the ledger cannot catch it.
#
# Exit 0 with no output -> allow the turn to end.
# Exit 0 with JSON      -> `decision:block` feeds the reason back to the model,
#                          which must update the page before stopping;
#                          `systemMessage` shows a note to the user only.
#                          This guard emits `decision:block` for a lagging page
#                          and `systemMessage` for a pointer that exists but
#                          yields no page name.
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
# saying nothing), and NO page at all.
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
    # `systemMessage`. A pointer naming a page that does NOT exist stays silent —
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
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        [ordered]@{
            systemMessage = ("进度页指针异常：$nameFile 存在，但读不出页名（空文件 / 全是空白 / 不可读）。" +
                             "守卫已回退到默认页名 project-progress.html —— 这只在页名恰好仍是它时才正确，" +
                             "否则守卫在看一个错误的文件。页名指针是页名的唯一事实源（AGENTS.md 第 5 节），" +
                             "请修正该文件再结束本轮。")
        } | ConvertTo-Json -Compress
        exit 0
    }

    # No page -> nothing to compare against, so there is no criterion to apply.
    # The premise is "the page exists and must not lag"; a page that was never
    # created cannot lag. "Not initialised yet" != "the page went missing" —
    # so exit silently (human decision; see AGENTS.md section 5).
    if (-not $page) { exit 0 }

    # The repo is the directory holding `.git`. Both layouts are supported: the
    # workspace root itself (self-hosted, the usual case here) and a `project/`
    # child (target layout).
    # ORDER MATTERS -- workspace root FIRST. A `project/` directory that merely
    # EXISTS is not a repo; if it were tried first and someone later ran
    # `git init` inside it, this guard would lock onto that inner, EMPTY repo,
    # find no HEAD, and go permanently silent -- which is exactly what it looks
    # like when it works. Both candidates stay: a fail-closed guard must not go
    # quietly dead when the layout shifts.
    # A candidate must RESOLVE as a git repo, not merely hold a `.git` entry
    # (GAP-009). The scoped EAP keeps git's stderr off the outer catch, which
    # would otherwise swallow this fail-closed check.
    $repo = @($ws, (Join-Path $ws 'project')) |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_ '.git')) -and
                (& { $ErrorActionPreference = 'Continue'
                     git -C $_ rev-parse --git-dir 2>$null })
            } |
            Select-Object -First 1
    if (-not $repo) { exit 0 }

    $head = (& git -C $repo rev-parse --short HEAD 2>$null)
    if (-not $head) { exit 0 }
    $head = $head.Trim()

    $content = Get-Content -LiteralPath $page -Raw
    # Case-insensitive: an uppercase SHA must still be COMPARED, not fall through
    # to the "no HEAD marker" silence (GAP-008).
    $m = [regex]::Match($content, '<div>head <b>([0-9a-fA-F]{7,40})</b></div>')
    if (-not $m.Success) { exit 0 }

    $recorded = $m.Groups[1].Value
    # Resolve both sides to FULL commit ids and compare those (GAP-008): any two
    # spellings naming the same commit match, while a fake SHA fails to resolve
    # and is correctly reported as lagging. `--quiet` keeps git's stderr off the
    # outer catch, which would otherwise swallow the verdict; `ToLower()` because
    # object ids are lowercase hex. `$head` stays short -- error-message wording.
    $headFull = (& git -C $repo rev-parse HEAD 2>$null)
    $recFull = (& git -C $repo rev-parse --verify --quiet "$($recorded.ToLower())^{commit}" 2>$null)
    if ($recFull -and $headFull -and ($recFull.Trim() -eq $headFull.Trim())) { exit 0 }

    # UTF-8 so the Chinese reason survives being captured off stdout.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $reason = "进度页落后于仓库：$name 记录的 HEAD 是 $recorded，而当前是 $head。" +
              "请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。" +
              "需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"

    [ordered]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
}
catch {
    # Never let the guard itself break a turn.
    exit 0
}
