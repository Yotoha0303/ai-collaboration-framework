# Stop-hook guard (MIGRATION FORWARDER): identifier numbers must not collide
# ACROSS BRANCHES.
#
# ⚠️ THIS FILE IS NOW A THIN FORWARDER. The guard logic lives in the Go binary
# `aicf-guard numbers` (aicf-guard/internal/numbers). See
# docs/adr/ADR-001-aicf-guard.md (§2.1, §3 "薄转发层契约").
#
# The ORIGINAL PowerShell implementation is preserved verbatim next to this file
# as `check-numbers.legacy.ps1` — it is the ORACLE for the differential test
# (aicf-guard/tools/parallel). It is NOT wired into any hook: do not run it in
# production. Retrieve the pre-migration version from git at any time with:
#   git show main:.claude/hooks/check-numbers.ps1
# (on the branch that introduced this forwarder; the legacy file is the same
# content, kept in-tree so the oracle does not depend on git history).
#
# =====================================================================
# WHY A FORWARDER RATHER THAN A DELETION (read before editing)
# =====================================================================
# The contract below is PUBLISHED: the hook configuration and the D3 self-test
# ruler both depend on it. Until the hook configuration itself is switched
# (M4, ADR §3), this file must keep presenting exactly that contract — which
# means it must never fail OPEN.
#
#   exit code 0 + empty stdout           -> no collision, allow the turn to end
#   exit code 1 + stderr                 -> a collision, OR a NON-BLOCKING
#                                           notice the user sees (git
#                                           unusable, untrustworthy exit
#                                           codes, candidate repo / refs /
#                                           tree unreadable, and — new here —
#                                           a missing binary)
#
# ⚠️ A MISSING BINARY TAKES THE NOTICE BRANCH (exit code 1 + stderr), exactly as
# ADR §3 prescribes for the progress forwarder ("二进制缺失 ⇒ 按原「git 不可用」
# 分支处置"). It is NOT silent: retiring a guard by deleting its binary must be
# visible.
#
# ⚠️ THIS FILE CANNOT BE EXERCISED ON A MACHINE WITHOUT PowerShell (the same
# limitation the progress forwarder records). Its correctness there is STATIC
# ONLY. Re-run the self-test on a machine WITH PowerShell before trusting
# the numbers group again; that is also the machine on which the differential
# test (aicf-guard/tools/parallel) can finally run for real.
#
# Layout (unchanged from the original): the binary sits next to this script.
#   <workspaceRoot>/.claude/hooks/check-numbers.ps1 | aicf-guard | check-numbers.legacy.ps1
# The binary is NOT tracked in git (ADR §6.8 R10: build artifacts stay out).

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

try {
    # <workspaceRoot>/.claude/hooks/check-numbers.ps1 -> <workspaceRoot>/.claude/hooks
    # Derived from THIS SCRIPT's location, never from the working directory: the
    # hook may run with any CWD. Same rule as the original.
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
        [Console]::Error.WriteLine("编号守卫未运行：$bin 缺失（aicf-guard 二进制未构建 / 未部署）。本轮未检查编号撞车。请先构建：cd aicf-guard && go build -o ../.claude/hooks/aicf-guard .")
        exit 1
    }

    # Pass the workspace explicitly: the binary cannot always reproduce the
    # .ps1's self-location (it may sit on PATH), and ADR §2.3 makes
    # --workspace the highest-priority layer. The value is this script's own
    # <ws>, derived the same way the original did.
    $ws = Split-Path -Parent (Split-Path -Parent $hooksDir)

    # Stream the child's stdout/stderr through UNCHANGED and propagate its exit
    # code.
    & $bin numbers --workspace $ws
    exit $LASTEXITCODE
}
catch {
    # The forwarder's own failure (binary present but not launchable, etc.).
    # Reported rather than swallowed: a silent catch here would retire the guard
    # with no trace, which is the exact failure this file exists to prevent.
    [Console]::Error.WriteLine("编号守卫未运行：转发层调用 aicf-guard 失败：$($_.Exception.Message)")
    exit 1
}
