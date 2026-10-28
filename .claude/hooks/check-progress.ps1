# Stop-hook guard (MIGRATION FORWARDER): the progress page must not lag MAINLINE.
#
# ⚠️ THIS FILE IS NOW A THIN FORWARDER. The guard logic lives in the Go binary
# `aicf-guard progress` (aicf-guard/internal/progress). See
# docs/adr/ADR-001-aicf-guard.md (§2.1, §3 "薄转发层契约").
#
# The ORIGINAL PowerShell implementation is preserved verbatim next to this file
# as `check-progress.legacy.ps1` — it is the ORACLE for the differential test
# (aicf-guard/tools/parallel). It is NOT wired into any hook: do not run it in
# production. Retrieve the pre-migration version from git at any time with:
#   git show 8e744cd:.claude/hooks/check-progress.ps1
#
# =====================================================================
# WHY A FORWARDER RATHER THAN A DELETION (read before editing)
# =====================================================================
# The contract below is PUBLISHED: the hook configuration and the D3 self-test
# ruler (.claude/hooks/self-test.ps1, A group) both depend on it. Until the hook
# configuration itself is switched (M4, ADR §3), this file must keep presenting
# exactly that contract — which means it must never fail OPEN.
#
#   exit code 0 + empty stdout           -> allow the turn to end
#   exit code 0 + {"decision":"block",…} -> the page lags; the reason is fed back
#                                           to the model, which must update the
#                                           page before stopping
#   exit code 1 + stderr                 -> a NON-BLOCKING notice the user sees
#                                           (git unusable, untrustworthy exit
#                                           codes, pointer naming no page, and
#                                           — new here — a missing binary)
#   exit code 0 + nothing                -> a DELIBERATE silence (no page, no
#                                           repo, no mainline, no HEAD marker)
#
# ⚠️ A MISSING BINARY TAKES THE NOTICE BRANCH (exit code 1 + stderr), exactly as
# ADR §3 prescribes ("二进制缺失 ⇒ 按原「git 不可用」分支处置"). It is NOT silent:
# retiring a guard by deleting its binary must be visible.
#
# ⚠️ KNOWN RESIDUAL — RECORDED, NOT FIXED HERE. On the Antigravity side a notice
# becomes a non-blocking `continue` (see .agents/hooks/stop-adapter.ps1:54-59),
# so a missing binary there degrades to "the turn proceeds anyway, with the
# notice in the reason". A stronger contract would emit an exit code OUTSIDE the
# guard's own {0,1} — so it could not be mistaken for a guard verdict — and teach
# the adapter to treat it as fatal. That is a CONTRACT CHANGE (it would also make
# self-test.ps1's D3 cell fail until the adapter covers the new code), so it is
# NOT made unilaterally here. Raised to the gate in docs/changes/005 §七 (U7).
#
# ⚠️ THIS FILE'S FAILURE MODE IS SILENCE. A wrong path derivation makes it never
# block, which is OBSERVATIONALLY IDENTICAL to the missing-page case. Verifying
# "silent when absent" therefore proves nothing at all. Re-verify with BOTH
# cases: (a) no page -> silent; (b) stale SHA in an existing page -> must emit
# decision:block. Only (b) has teeth.
#
# ⚠️ THIS FILE CANNOT BE EXERCISED ON THE MACHINE IT WAS WRITTEN ON (`pwsh` and
# `powershell` are both absent — measured 2026-10-28). Its correctness here is
# STATIC ONLY. Re-run the self-test on a machine WITH PowerShell before trusting
# the A group again; that is also the machine on which the differential test
# (aicf-guard/tools/parallel) can finally run for real.
#
# Layout (unchanged from the original): the binary sits next to this script.
#   <workspaceRoot>/.claude/hooks/check-progress.ps1 | aicf-guard | check-progress.legacy.ps1
# The binary is NOT tracked in git (ADR §6.8 R10: build artifacts stay out).

$ErrorActionPreference = 'Stop'

# UTF-8 for BOTH channels, before either is written: the notice branch writes
# Chinese to stderr and the block path writes Chinese to stdout. Wrapped because
# this setter throws on hosts that cannot change the console encoding, and an
# unguarded throw here would kill the guard (measured — see the legacy file's
# header, the "A7-f2" case).
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

try {
    # <workspaceRoot>/.claude/hooks/check-progress.ps1 -> <workspaceRoot>/.claude/hooks
    # Derived from THIS SCRIPT's location, never from the working directory: the
    # hook may run with any CWD. Same rule as the original (legacy line 185).
    $hooksDir = Split-Path -Parent $PSCommandPath
    $bin = Join-Path $hooksDir 'aicf-guard'
    if (-not (Test-Path -LiteralPath $bin)) {
        # Windows builds carry the extension.
        $exe = Join-Path $hooksDir 'aicf-guard.exe'
        if (Test-Path -LiteralPath $exe) { $bin = $exe }
    }

    if (-not (Test-Path -LiteralPath $bin)) {
        # FAIL CLOSED — notice, never silence. The wording mirrors the
        # "git unusable" notice (same channel, same shape), because from the
        # hook host's point of view this is the same situation: the guard could
        # not run, so this turn was NOT checked.
        [Console]::Error.WriteLine("进度页守卫未运行：$bin 缺失（aicf-guard 二进制未构建 / 未部署）。本轮未检查进度页是否落后。请先构建：cd aicf-guard && go build -o ../.claude/hooks/aicf-guard .")
        exit 1
    }

    # Pass the workspace explicitly: the binary cannot always reproduce the
    # .ps1's self-location (it may sit on PATH), and ADR §2.3 makes
    # --workspace the highest-priority layer. The value is this script's own
    # <ws>, derived the same way the original did.
    $ws = Split-Path -Parent (Split-Path -Parent $hooksDir)

    # Stream the child's stdout/stderr through UNCHANGED and propagate its exit
    # code. With the default redirection the child writes to this process's
    # streams, so a decision:block line reaches the host intact and the notice
    # branch's stderr stays on stderr.
    & $bin progress --workspace $ws
    exit $LASTEXITCODE
}
catch {
    # The forwarder's own failure (binary present but not launchable, etc.).
    # Reported rather than swallowed: a silent catch here would retire the guard
    # with no trace, which is the exact failure this file exists to prevent.
    [Console]::Error.WriteLine("进度页守卫未运行：转发层调用 aicf-guard 失败：$($_.Exception.Message)")
    exit 1
}
