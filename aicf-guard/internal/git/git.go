// Package git is the SINGLE place a git exit code is read (ADR-001 §1.3.1,
// "THE ONE RULE"). Every git call whose result decides something goes through
// Checked and is judged by Result.Exit == 0; Result.Text is a PAYLOAD only.
//
// # The GIT_* env family (ADR §1.3.3, GAP-013① + GAP-031)
//
// Checked clears the 9-variable GIT_* family from the CHILD process's
// environment before launching git. The parent process environment is NOT
// mutated (the child receives a filtered copy built from os.Environ()), so
// concurrent calls are goroutine-safe — unlike the .ps1 original, which saved
// and restored process env in a single-threaded host.
//
// Why the whole family and not just GIT_DIR: clearing only GIT_DIR is
// insufficient. GIT_OBJECT_DIRECTORY / GIT_COMMON_DIR hijack
// `git rev-parse --verify <ref>^{commit}` (measured 2026-10-17 as a regression
// of cell A11 — exactly what that cell exists to catch). The other seven are
// cleared anyway: clearing costs nothing, and "which one hijacks" is a git
// implementation detail nobody should have to remember. Family members are NOT
// reducible.
//
// # Fail-closed (ADR §1.3.1)
//
// A launch failure (git not on PATH, zero-byte binary, etc.) returns
// Exit == launchFailSentinel (-1), so callers' `Exit == 0` checks stay false —
// matching the .ps1 where a failed launch leaves $null and `$null -eq 0` is
// false. The guard never waves a stale page through because git could not run.
package git

import (
	"bytes"
	"os"
	"os/exec"
	"strings"
)

// Result is the return shape of Checked. Exit is the CRITERION; Text is PAYLOAD.
// Callers MUST test `.Exit == 0` (or `!= 0`), never the truthiness of `.Text`.
type Result struct {
	Exit int
	Text string
}

// launchFailSentinel marks "git could not be launched at all" (not on PATH,
// zero-byte binary, ApplicationFailedException, etc.). It is negative so
// `Result.Exit == 0` stays false (fail-closed), matching the .ps1's `$null`.
// Callers should compare `!= 0` (covers both launch failure and non-zero exit);
// this sentinel is exported only so tests can assert the exact shape.
const launchFailSentinel = -1

// gitEnvFamily is the 9-variable family (ADR §1.3.3). NOT reducible — see the
// package doc. Order matches check-progress.ps1:128-138 for diff-ability.
var gitEnvFamily = []string{
	"GIT_DIR",
	"GIT_WORK_TREE",
	"GIT_OBJECT_DIRECTORY",
	"GIT_COMMON_DIR",
	"GIT_INDEX_FILE",
	"GIT_ALTERNATE_OBJECT_DIRECTORIES",
	"GIT_CEILING_DIRECTORIES",
	"GIT_NAMESPACE",
	"GIT_PREFIX",
}

// zeroOID is the all-zero object id, naming no object in any repo. Used by
// Canary (the negative canary, ADR §1.3.2).
const zeroOID = "0000000000000000000000000000000000000000"

// Checked runs `git <args...>` with the GIT_* family cleared from the child
// environment, returning {Exit, Text}. The parent process environment is NOT
// mutated (the child receives a filtered copy), so concurrent calls are safe.
//
// Exit is the ONLY criterion:
//   - 0                     → git launched and exited 0 (success);
//   - launchFailSentinel    → git could NOT be launched (fail-closed);
//   - any other non-zero    → git launched and exited non-zero (failure).
//
// All three non-zero cases satisfy `Exit != 0`. Text is the trimmed stdout and
// is NEVER the criterion (comparing outputs as strings was itself a silent
// path — the V13 case: a shim that always exits 128 while printing a constant
// made both sides "equal" garbage).
func Checked(args ...string) Result {
	cmd := exec.Command("git", args...)
	cmd.Env = filterGitFamily(os.Environ())
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			// git launched and exited non-zero. ee.ExitCode() is the real code.
			return Result{Exit: ee.ExitCode(), Text: strings.TrimSpace(stdout.String())}
		}
		// Launch failure (git not on PATH, zero-byte binary, etc.): fail-closed.
		// Leaving Exit as launchFailSentinel keeps `Exit == 0` false.
		return Result{Exit: launchFailSentinel, Text: ""}
	}
	return Result{Exit: 0, Text: strings.TrimSpace(stdout.String())}
}

// filterGitFamily returns environ with every GIT_* family member removed. The
// returned slice is suitable as exec.Cmd.Env (it does NOT mutate the parent
// process environment, which is what makes Checked goroutine-safe).
func filterGitFamily(environ []string) []string {
	out := make([]string, 0, len(environ))
	for _, kv := range environ {
		name, _, ok := strings.Cut(kv, "=")
		if !ok {
			// A malformed entry with no '=' — drop it (can't be a valid env var).
			continue
		}
		if isGitEnvFamily(name) {
			continue
		}
		out = append(out, kv)
	}
	return out
}

// isGitEnvFamily reports whether name is a member of the GIT_* family. Linear
// scan over a 9-element slice — cheaper than a map allocation per call.
func isGitEnvFamily(name string) bool {
	for _, n := range gitEnvFamily {
		if n == name {
			return true
		}
	}
	return false
}

// Probe is the positive probe (ADR §1.3.2): `git --version` MUST exit 0.
// Judging by exit code (not output truthiness) catches both "git not on PATH"
// (launch failure → Exit == launchFailSentinel) and "zero-byte git.exe on PATH"
// (launch failure too). `Get-Command git` only proves the name resolves and is
// NOT a sufficient probe — measured (GAP-013-2). Returns true iff git launches
// AND exits 0.
func Probe() bool {
	return Checked("--version").Exit == 0
}

// Canary is the NEGATIVE canary (ADR §1.3.2): `git rev-parse --verify
// <zeroOID>^{commit}` MUST exit non-zero. Together with Probe, this forces git
// to return DIFFERENT exit codes for two different inputs, which is what makes
// the exit code trustworthy rather than assumed:
//   - a shim that always exits 0 passes Probe and is caught here;
//   - a shim that always exits non-zero is caught by Probe.
//
// Returns true iff git's exit code is trustworthy — i.e., the must-fail input
// correctly returned non-zero AND git actually launched (not a launch failure).
// Callers MUST call Probe() first; if git cannot launch, Canary() returns false
// (defensive: no exit code to trust).
func Canary() bool {
	r := Checked("rev-parse", "--verify", "--quiet", zeroOID+"^{commit}")
	return r.Exit != 0 && r.Exit != launchFailSentinel
}
