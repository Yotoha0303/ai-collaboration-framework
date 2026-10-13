# PreInvocation hook for Antigravity:
# Dynamically injects the truncated tail of AGENTS.md (beyond the 24,000-byte
# per-file user_rules cap) without modifying AGENTS.md or maintaining a second
# copy (strictly preserving D4 SSOT).
#
# Future-proof design:
# 1. Byte-accurate boundary detection: reads AGENTS.md line-by-line in UTF-8,
#    starts slicing at 23,000 bytes (1,000-byte overlap safety margin before
#    the 24,000-byte truncation boundary so no line is ever dropped).
# 2. Automatic multi-chunking: if AGENTS.md grows in the future (e.g. 60KB,
#    100KB+), the tail is automatically split on line boundaries into chunks of
#    at most 24,000 UTF-8 bytes each, emitted as sequential ephemeralMessage
#    entries in injectSteps.
# 3. Fail-safe: any unexpected error outputs `{}` and exits 0 so the session
#    is never bricked.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

try {
    # <ws>/.agents/hooks/inject-agents-tail.ps1 -> <ws>
    $hooksDir = Split-Path -Parent $PSCommandPath
    $agentsDir = Split-Path -Parent $hooksDir
    $ws = Split-Path -Parent $agentsDir

    $agentsFile = Join-Path $ws 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $agentsFile)) {
        Write-Output '{}'
        exit 0
    }

    $utf8 = [System.Text.Encoding]::UTF8
    $rawBytes = [System.IO.File]::ReadAllBytes($agentsFile)

    # Antigravity per-file cap is 24,000 bytes. If AGENTS.md fits, nothing to inject.
    $singleFileCap = 24000
    $sliceStartBytes = 23000  # 1,000-byte overlap buffer so boundary lines are never lost
    $chunkMaxBytes = 24000    # Pre-reserved multi-chunk cap for future AGENTS.md growth

    if ($rawBytes.Length -le $singleFileCap) {
        Write-Output '{}'
        exit 0
    }

    $lines = [System.IO.File]::ReadAllLines($agentsFile, $utf8)
    $cumBytes = 0
    $startLineIdx = 0
    $foundStart = $false

    for ($i = 0; $i -lt $lines.Length; $i++) {
        # +1 for LF (or +2 for CRLF); use actual line UTF-8 byte count + 2 as conservative bound
        $lineBytes = $utf8.GetByteCount($lines[$i]) + 2
        if ((-not $foundStart) -and (($cumBytes + $lineBytes) -ge $sliceStartBytes)) {
            $startLineIdx = $i
            $foundStart = $true
            break
        }
        $cumBytes += $lineBytes
    }

    if (-not $foundStart) {
        Write-Output '{}'
        exit 0
    }

    # Group remaining lines into chunks <= $chunkMaxBytes (future-proof for arbitrary growth)
    $chunks = New-Object System.Collections.Generic.List[string]
    $currentLines = New-Object System.Collections.Generic.List[string]
    $currentBytes = 0
    $chunkStartLine = $startLineIdx + 1

    for ($i = $startLineIdx; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $lineBytes = $utf8.GetByteCount($line) + 1
        if (($currentBytes + $lineBytes -gt $chunkMaxBytes) -and ($currentLines.Count -gt 0)) {
            $header = "[AGENTS.md 自动补齐分片 (lines $chunkStartLine-$i / total $($lines.Length), UTF-8 >24KB 零侵入续载)]`n"
            $chunks.Add($header + ($currentLines -join "`n"))
            $currentLines.Clear()
            $currentBytes = 0
            $chunkStartLine = $i + 1
        }
        $currentLines.Add($line)
        $currentBytes += $lineBytes
    }

    if ($currentLines.Count -gt 0) {
        $header = "[AGENTS.md 自动补齐分片 (lines $chunkStartLine-$($lines.Length) / total $($lines.Length), UTF-8 >24KB 零侵入续载)]`n"
        $chunks.Add($header + ($currentLines -join "`n"))
    }

    $injectSteps = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in $chunks) {
        $injectSteps.Add([ordered]@{ ephemeralMessage = $chunk })
    }

    $result = [ordered]@{ injectSteps = $injectSteps }
    Write-Output ($result | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}
catch {
    Write-Output '{}'
    exit 0
}
