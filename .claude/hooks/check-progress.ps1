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
#
# Why PowerShell and not bash: if Git for Windows lives somewhere that keeps
# `usr\bin` off the Windows PATH, a hook command of
# `bash ...` fails with "not recognized". System32 is always on PATH, so
# `powershell` resolves. The script also derives every path from its own
# location rather than from CLAUDE_PROJECT_DIR, so it works regardless of how
# the hook is invoked or what the working directory is.
#
# Layout this script assumes (the AI framework lives OUTSIDE the repo, by human
# decision — so that it cannot be shipped as a deliverable):
#
#     <workspaceRoot>/                     <- session working directory
#         CLAUDE.md                        <- thin entry point (imports AGENTS.md)
#         .claude/hooks/check-progress.ps1 <- this file
#         .claude/progress-page.txt        <- ONE line: the page's file name
#         <page>                           <- the page, sibling of .claude/
#         project/                         <- the repo (contains .git)
#
# The page NAME is read from `.claude/progress-page.txt`, not hardcoded: the page
# is renamed as the project progresses, and a rename must not require editing
# this script (or silently kill the guard).
#
# Both lookups below resolve from the script's OWN location, never from the
# working directory — the hook may run with any CWD.
#
# Silent in two cases on purpose: no git HEAD, and no HEAD marker in the page
# (the page was restructured beyond recognition; a false alarm on every stop is
# worse than saying nothing). A MISSING page is NOT silent any more — see below.
#
# NOTE: these lookups fail closed by design, so a WRONG path derivation makes
# this guard silently never block. If the layout or the page name ever changes,
# re-verify with the negative case (page carrying a stale SHA must emit
# decision:block), not just the positive one (matching SHA must stay silent).

$ErrorActionPreference = 'Stop'

try {
    # <workspaceRoot>/.claude/hooks/check-progress.ps1  ->  <workspaceRoot>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $claudeDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $claudeDir

    # Page NAME comes from a one-line pointer file so the page can be renamed
    # without touching this script. Falls back to the current name if absent.
    $name = 'project-progress.html'
    $nameFile = Join-Path $claudeDir 'progress-page.txt'
    if (Test-Path -LiteralPath $nameFile) {
        $fromFile = Get-Content -LiteralPath $nameFile -Raw
        if ($fromFile) { $name = $fromFile.Trim() }
    }

    # The page is the sibling of `.claude/` in the current layout; in the
    # pre-move layout (`.claude/` inside the repo) it is the sibling of the repo.
    # Trying both keeps the guard alive across a revert of the move — a guard
    # that fails closed must not go quietly dead when the layout shifts.
    $page = @((Join-Path $ws $name),
              (Join-Path (Split-Path -Parent $ws) $name)) |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

    # A missing page is a REAL anomaly, not a clone scenario: the framework lives
    # only on this machine. Tell the user instead of failing closed in silence
    # (D3 — a guard that swallows the real case is worse than no guard).
    if (-not $page) {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $expected = Join-Path $ws $name
        [ordered]@{ systemMessage = "进度页缺失：$expected （页名取自 .claude/progress-page.txt）。" +
                                     "该页是记录的第二投影，缺失即 '两处成熟度不一致' 的隐患。" +
                                     "请确认页名是否正确，或恢复该页面。" } |
            ConvertTo-Json -Compress
        exit 0
    }

    # The repo is the `project/` child; the second candidate is the pre-move
    # layout, where the directory holding `.claude/` IS the repo.
    $repo = @((Join-Path $ws 'project'), $ws) |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ '.git') } |
            Select-Object -First 1
    if (-not $repo) { exit 0 }

    $head = (& git -C $repo rev-parse --short HEAD 2>$null)
    if (-not $head) { exit 0 }
    $head = $head.Trim()

    $content = Get-Content -LiteralPath $page -Raw
    $m = [regex]::Match($content, '<div>head <b>([0-9a-f]{7,40})</b></div>')
    if (-not $m.Success) { exit 0 }

    $recorded = $m.Groups[1].Value
    if ($recorded -eq $head) { exit 0 }

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
