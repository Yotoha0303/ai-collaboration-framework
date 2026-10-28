// Command parallel is the M0 differential harness runner: it runs every named
// scenario against `aicf-guard progress` and, when a PowerShell interpreter is
// supplied, against the original check-progress.ps1, then compares exit code,
// stdout and stderr byte for byte (ADR-001 §2.5 / §6.1).
//
// It is a DEVELOPER TOOL, deliberately NOT an aicf-guard subcommand: ADR §2.1
// forbids inventing new subcommand names ("除 --version 外不发明新子命令名"), and
// during migration the subcommand names have to stay comparable with the .ps1.
//
// Usage:
//
//	go run ./tools/parallel                                  # Go side only → SKIP
//	go run ./tools/parallel -guard /tmp/aicf-guard
//	go run ./tools/parallel -guard /tmp/aicf-guard -oracle pwsh \
//	    -legacy ../.claude/hooks/check-progress.legacy.ps1
//
// Exit codes distinguish the four verdicts (never collapse SKIP into PASS):
//
//	0 PASS · 1 DIFF · 2 SKIP · 3 ERROR
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"aicf-guard/internal/parallel"
)

func main() {
	guard := flag.String("guard", filepath.Join(".", "aicf-guard"), "path to the built aicf-guard binary (required)")
	oracle := flag.String("oracle", os.Getenv("AICF_ORACLE"),
		"PowerShell interpreter that can run the .ps1 (default: $AICF_ORACLE). Empty → no comparison, verdict SKIP")
	legacy := flag.String("legacy", "", "path to the original check-progress.ps1 (required when -oracle is set)")
	timeout := flag.Duration("timeout", 30*time.Second, "per-process timeout")
	flag.Parse()

	rep := parallel.Run(parallel.Options{
		GuardBinary:  *guard,
		Oracle:       *oracle,
		LegacyScript: *legacy,
		Timeout:      *timeout,
	})
	fmt.Print(rep.Summary())
	os.Exit(rep.Kind.ExitCode())
}
