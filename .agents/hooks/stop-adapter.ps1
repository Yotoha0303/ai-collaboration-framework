# Stop hook adapter for Antigravity:
# Bridges existing Claude Code Stop hooks (`.claude/hooks/check-progress.ps1`
# and `.claude/hooks/check-numbers.ps1`) to Antigravity's `.agents/hooks.json`
# Stop contract WITHOUT modifying the original scripts.
#
# Protocol translation:
# - Claude Code `{"decision":"block","reason":"..."}` -> Antigravity `{"decision":"continue","reason":"..."}`
# - Claude Code `exit 1` + stderr (notice/collision)  -> Antigravity `{"decision":"continue","reason":"..."}` on first stop
# - Claude Code `exit 0` with empty stdout            -> Antigravity `{"decision":"allow"}`

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

try {
    # <ws>/.agents/hooks/stop-adapter.ps1 -> <ws>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $agentsDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $agentsDir

    $claudeHooksDir = Join-Path (Join-Path $ws '.claude') 'hooks'
    $progressScript = Join-Path $claudeHooksDir 'check-progress.ps1'
    $numbersScript = Join-Path $claudeHooksDir 'check-numbers.ps1'

    $blockReasons = New-Object System.Collections.Generic.List[string]
    $notices = New-Object System.Collections.Generic.List[string]

    function Invoke-ClaudeHook([string]$ScriptPath) {
        if (-not (Test-Path -LiteralPath $ScriptPath)) { return }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $psi.WorkingDirectory = $ws
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        if ($stdout) {
            try {
                $parsed = $stdout | ConvertFrom-Json
                if ($parsed.decision -eq 'block' -and $parsed.reason) {
                    $blockReasons.Add([string]$parsed.reason)
                }
            } catch { }
        }
        # Notice-only channel (exit 1 + stderr, e.g., check-numbers.ps1 cross-branch notice):
        # In Claude Code this informs via stderr without blocking the turn (check-numbers.ps1 line 18).
        if ($exitCode -ne 0 -and $stderr) {
            $notices.Add([string]$stderr)
            [Console]::Error.WriteLine($stderr)
        }
    }

    Invoke-ClaudeHook $progressScript
    Invoke-ClaudeHook $numbersScript

    if ($blockReasons.Count -gt 0) {
        $allMessages = New-Object System.Collections.Generic.List[string]
        $allMessages.AddRange($blockReasons)
        if ($notices.Count -gt 0) { $allMessages.AddRange($notices) }
        $combined = ($allMessages -join "`n`n")
        Write-Output ([ordered]@{ decision = 'continue'; reason = $combined } | ConvertTo-Json -Compress)
        exit 0
    }

    Write-Output ([ordered]@{ decision = 'allow' } | ConvertTo-Json -Compress)
    exit 0
}
catch {
    Write-Output ([ordered]@{ decision = 'allow' } | ConvertTo-Json -Compress)
    exit 0
}
