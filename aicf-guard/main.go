// aicf-guard is the single binary that consolidates the five PowerShell guards
// (check-progress, check-numbers, inject-agents-tail, stop-adapter, self-test)
// per ADR-001 (docs/adr/ADR-001-aicf-guard.md).
//
// Shipped so far: the module skeleton, --version (M0 1st dispatch) and progress
// (M0 2nd dispatch). The remaining subcommands land later (numbers = M1;
// inject/adapter = M2; selftest = M3; doctor = M4 per ADR §3 / §8.2 R7). The
// shared libraries (internal/git, internal/workspace, internal/mainline,
// internal/sha, internal/page) back the shipped subcommands.
package main

import (
	"fmt"
	"io"
	"os"

	"aicf-guard/internal/progress"
)

// version and commit are build-time injected (ADR §2.1 R4) via:
//
//	go build -ldflags "-X main.version=v0.1.0 -X main.commit=$(git rev-parse --short HEAD)"
//
// Defaults ("dev"/"unknown") apply when NOT injected (e.g. a plain `go build`
// without -ldflags). --version MUST NOT read the workspace, call git, or depend
// on any external state — it returns these constants verbatim, so any CWD /
// environment yields a stable output (ADR §2.1: "纯返回构建期常量").
var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run executes the CLI and returns the exit code. Separated from main() so tests
// can call it with synthetic args and capture stdout/stderr without os.Exit.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		printUsage(stderr)
		return 2
	}
	switch args[0] {
	case "--version", "-V":
		// ADR §2.1 R4: "aicf-guard <semver> (<commit-hash>)" — one line to
		// stdout, exit 0. Pure build-time constants; no external state.
		fmt.Fprintf(stdout, "aicf-guard %s (%s)\n", version, commit)
		return 0
	case "-h", "--help":
		printUsage(stdout)
		return 0
	case "progress":
		// ADR §1.2 / §6.1: the exit code contract is the published one. All the
		// logic — including the deliberate silences — lives in the package so it
		// can be exercised without a process boundary.
		return progress.Run(args[1:], stdout, stderr, progress.DefaultDeps())
	case "numbers", "inject", "adapter", "selftest", "doctor":
		// Not yet ported. Placeholder exits 1 with a clear stderr line so it is
		// never mistaken for a silent success (fail-closed).
		fmt.Fprintf(stderr, "aicf-guard: %q not implemented yet (see ADR-001 §3 for the milestone)\n", args[0])
		return 1
	default:
		fmt.Fprintf(stderr, "aicf-guard: unknown subcommand %q\n", args[0])
		printUsage(stderr)
		return 2
	}
}

// printUsage writes the help text to w. Used for both -h/--help (stdout, exit 0)
// and the error paths (stderr, exit 2).
func printUsage(w io.Writer) {
	fmt.Fprintln(w, "usage: aicf-guard <subcommand> [flags]")
	fmt.Fprintln(w, "       aicf-guard --version")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "subcommands (ADR-001 §2.1):")
	fmt.Fprintln(w, "  progress   check progress page against mainline")
	fmt.Fprintln(w, "  numbers    check identifier numbers across branches (M1)")
	fmt.Fprintln(w, "  inject     inject AGENTS.md tail for Antigravity (M2)")
	fmt.Fprintln(w, "  adapter    adapt progress/numbers to Antigravity Stop protocol (M2)")
	fmt.Fprintln(w, "  selftest   run the D3 self-test ruler (M3)")
	fmt.Fprintln(w, "  doctor     self-check binary integrity (M4)")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "flags:")
	fmt.Fprintln(w, "  --version  print \"aicf-guard <semver> (<commit-hash>)\" and exit 0")
	fmt.Fprintln(w, "  -h, --help print this help and exit 0")
}
