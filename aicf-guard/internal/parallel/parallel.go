// Package parallel is the M0 differential harness: it runs the SAME named
// scenario against `aicf-guard progress` and against the original
// check-progress.ps1 in two identically-built sandboxes, and compares exit
// code / stdout / stderr byte for byte (ADR-001 §2.5, §6.1).
//
// # Why this exists and what it does NOT prove
//
// ADR §6.1 makes byte-equality against the .ps1 the hard criterion for a
// subcommand's migration. That criterion cannot be evaluated without a
// PowerShell runtime, and the machine this was developed on has none
// (`command -v pwsh` and `command -v powershell` both exit 1 — measured
// 2026-10-28). So the harness is built to be INJECTABLE instead of assumed:
//
//   - with AICF_ORACLE unset it runs the Go side only and reports SKIP for every
//     comparison. SKIP is not PASS, and Report.Kind makes that impossible to
//     confuse (see ExitCode);
//   - with AICF_ORACLE set to a PowerShell interpreter it performs the real
//     byte comparison.
//
// A green harness without an oracle therefore means "the scenarios run and the
// Go side matches its documented expectation", NOT "the port is equivalent".
// docs/changes/005 records the parity criterion as UNVERIFIED for that reason.
//
// # The scenarios
//
// Each one mirrors a named cell of .claude/hooks/self-test.ps1's A group (the
// D3 ruler for this very guard), plus the notice and silence branches that the
// ruler reaches through other groups. Naming them the same way is deliberate:
// when an oracle becomes available, the reader can line the two lists up.
package parallel

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// RunKind is the overall verdict. The three values are mutually exclusive and
// report why the run ended the way it did — the distinction SKIP vs PASS is the
// whole point (D3: a harness that cannot tell "checked" from "did not check"
// hides exactly the failures it exists to prevent).
type RunKind int

const (
	// KindPass: an oracle was supplied and every scenario matched byte for byte.
	KindPass RunKind = iota
	// KindDiff: an oracle was supplied and at least one scenario differed.
	KindDiff
	// KindSkip: no oracle was supplied, so no comparison happened.
	KindSkip
	// KindError: the harness could not run (missing binary, missing .ps1,
	// setup failure). Never conflated with a pass.
	KindError
)

func (k RunKind) String() string {
	switch k {
	case KindPass:
		return "PASS"
	case KindDiff:
		return "DIFF"
	case KindSkip:
		return "SKIP"
	case KindError:
		return "ERROR"
	}
	return "UNKNOWN"
}

// ExitCode maps the verdict onto a process exit code so a shell can tell the
// four outcomes apart:
//
//	0 PASS · 1 DIFF · 2 SKIP · 3 ERROR
//
// SKIP deliberately does NOT reuse 0. A caller that wants parity enforced can
// treat 2 as fatal (`test $? -eq 0`), while a caller that merely wants "did the
// Go side behave" can accept 0 or 2.
func (k RunKind) ExitCode() int {
	switch k {
	case KindPass:
		return 0
	case KindDiff:
		return 1
	case KindSkip:
		return 2
	}
	return 3
}

// Result is one process run, normalised so the two sides are comparable.
type Result struct {
	Exit   int
	Stdout string
	Stderr string
}

// String renders a Result for a diff report (one line, so a report stays
// greppable).
func (r Result) String() string {
	return fmt.Sprintf("exit=%d stdout=%q stderr=%q", r.Exit, r.Stdout, r.Stderr)
}

// Comparison is one scenario's outcome.
type Comparison struct {
	Name string
	// Go is what `aicf-guard progress` did.
	Go Result
	// Oracle is what the .ps1 did. Zero when no oracle was supplied.
	Oracle Result
	// Comparable is false when the oracle could not be run for this scenario.
	Comparable bool
	// Note carries a mismatch description, or the reason the comparison was
	// skipped.
	Note string
}

// Matches reports whether the two sides agreed byte for byte.
func (c Comparison) Matches() bool {
	return c.Comparable &&
		c.Go.Exit == c.Oracle.Exit &&
		c.Go.Stdout == c.Oracle.Stdout &&
		c.Go.Stderr == c.Oracle.Stderr
}

// Report is the whole run.
type Report struct {
	Kind        RunKind
	Comparisons []Comparison
	// Err is set only for KindError.
	Err error
}

// Summary renders one line per scenario plus a final verdict line. The verdict
// line always starts with the Kind, so `grep '^SKIP'` finds exactly the
// scenarios that were not compared.
func (r Report) Summary() string {
	var b strings.Builder
	for _, c := range r.Comparisons {
		switch {
		case !c.Comparable:
			fmt.Fprintf(&b, "SKIP  %s — %s\n", c.Name, c.Note)
		case c.Matches():
			fmt.Fprintf(&b, "PASS  %s — %s\n", c.Name, c.Go)
		default:
			fmt.Fprintf(&b, "DIFF  %s\n      go:     %s\n      oracle: %s\n",
				c.Name, c.Go, c.Oracle)
		}
	}
	if r.Err != nil {
		fmt.Fprintf(&b, "VERDICT %s — %v\n", r.Kind, r.Err)
	} else {
		fmt.Fprintf(&b, "VERDICT %s — %d scenario(s)\n", r.Kind, len(r.Comparisons))
	}
	return b.String()
}

// Options configures a run.
type Options struct {
	// GuardBinary is the path to a built aicf-guard. REQUIRED: the harness tests
	// the process boundary (exit code + streams), so calling the package
	// functions directly would test something else.
	GuardBinary string
	// Oracle is the PowerShell interpreter that can run the .ps1, or "" for a
	// Go-only run (→ KindSkip).
	Oracle string
	// LegacyScript is the path to the original check-progress.ps1 to run through
	// Oracle. Ignored when Oracle is "".
	LegacyScript string
	// Timeout bounds each process run. Zero means 30s.
	Timeout time.Duration
	// Scenarios overrides the scenario list. Nil means Scenarios(). Tests use
	// this to drive the four verdicts with tiny synthetic scenarios instead of
	// the real list (whose expectations a fake binary cannot satisfy).
	Scenarios []Scenario
}

// Run executes every scenario twice (fresh sandbox each time) and compares.
//
// Each side gets its OWN sandbox built by the same recipe, because both the
// guard and the .ps1 mutate nothing but must not be able to influence each
// other through a shared directory tree. The recipe is deterministic only in
// structure (commit ids differ between the two sandboxes) — that is fine and
// intended: every scenario writes the page from the SANDBOX'S OWN HEAD, so both
// sides see "the page matches my trunk", not "the page holds a fixed SHA".
func Run(opts Options) Report {
	if opts.GuardBinary == "" {
		return Report{Kind: KindError, Err: errors.New("GuardBinary is required")}
	}
	if _, err := os.Stat(opts.GuardBinary); err != nil {
		return Report{Kind: KindError, Err: fmt.Errorf("guard binary %q: %w", opts.GuardBinary, err)}
	}
	timeout := opts.Timeout
	if timeout == 0 {
		timeout = 30 * time.Second
	}
	compare := opts.Oracle != ""
	if compare && opts.LegacyScript == "" {
		return Report{Kind: KindError, Err: errors.New("Oracle set but LegacyScript is empty")}
	}

	scenarios := opts.Scenarios
	if scenarios == nil {
		scenarios = Scenarios()
	}

	rep := Report{Kind: KindSkip}
	for _, sc := range scenarios {
		cmp := Comparison{Name: sc.Name}

		// Platform-gated scenario: report SKIP with the reason and never count it
		// as a comparison (a scenario that cannot run must not look like one that
		// ran and matched).
		if sc.SkipReason != nil {
			if why := sc.SkipReason(); why != "" {
				cmp.Comparable = false
				cmp.Note = "not applicable on this platform: " + why
				rep.Comparisons = append(rep.Comparisons, cmp)
				continue
			}
		}

		goRes, err := runScenario(sc, opts.GuardBinary, timeout)
		if err != nil {
			rep.Kind = KindError
			rep.Err = fmt.Errorf("scenario %q (go side): %w", sc.Name, err)
			rep.Comparisons = append(rep.Comparisons, cmp)
			return rep
		}
		cmp.Go = goRes

		if msg := sc.Expect.check(goRes); msg != "" {
			rep.Kind = KindError
			rep.Err = fmt.Errorf("scenario %q violates its documented expectation: %s", sc.Name, msg)
			rep.Comparisons = append(rep.Comparisons, cmp)
			return rep
		}

		if !compare {
			cmp.Comparable = false
			cmp.Note = "oracle not configured (set AICF_ORACLE); the .ps1 was NOT run, so parity is UNVERIFIED"
			rep.Comparisons = append(rep.Comparisons, cmp)
			continue
		}

		orRes, err := runScenarioExt(sc, opts.LegacyScript, opts.Oracle, timeout)
		if err != nil {
			rep.Kind = KindError
			rep.Err = fmt.Errorf("scenario %q (oracle side): %w", sc.Name, err)
			rep.Comparisons = append(rep.Comparisons, cmp)
			return rep
		}
		cmp.Oracle = orRes
		cmp.Comparable = true
		if !cmp.Matches() {
			rep.Kind = KindDiff
			cmp.Note = "byte mismatch"
		}
		rep.Comparisons = append(rep.Comparisons, cmp)
	}
	// PASS requires at least one COMPARED scenario: an all-skipped run (no
	// platform-applicable scenarios) must stay SKIP, never become a green pass.
	if compare && rep.Kind == KindSkip && anyComparable(rep.Comparisons) {
		rep.Kind = KindPass
	}
	return rep
}

// anyComparable reports whether at least one comparison actually happened.
func anyComparable(cs []Comparison) bool {
	for _, c := range cs {
		if c.Comparable {
			return true
		}
	}
	return false
}

// runScenario builds a sandbox and runs the guard against it.
func runScenario(sc Scenario, guardBinary string, timeout time.Duration) (Result, error) {
	dir, err := os.MkdirTemp("", "aicf-parallel-go-")
	if err != nil {
		return Result{}, err
	}
	defer os.RemoveAll(dir)
	env, err := sc.Make(dir)
	if err != nil {
		return Result{}, fmt.Errorf("sandbox setup: %w", err)
	}
	return runProcess(guardBinary, []string{"progress", "--workspace", dir}, dir, env, timeout)
}

// runScenarioExt builds an identical sandbox and runs the legacy .ps1 inside it.
//
// The .ps1 is placed at <sb>/.claude/hooks/check-progress.ps1 because it derives
// the workspace root from its OWN path (Split-Path -Parent $PSCommandPath,
// check-progress.ps1:185) — running it from elsewhere would resolve a different
// workspace and compare the wrong things. The interpreter is invoked with the
// same flags the hook configuration uses (.claude/settings.json), so the
// command line is the shipped one, not an easier one.
func runScenarioExt(sc Scenario, legacyScript, oracle string, timeout time.Duration) (Result, error) {
	src, err := os.ReadFile(legacyScript)
	if err != nil {
		return Result{}, fmt.Errorf("reading legacy script: %w", err)
	}
	dir, err := os.MkdirTemp("", "aicf-parallel-ps-")
	if err != nil {
		return Result{}, err
	}
	defer os.RemoveAll(dir)
	env, err := sc.Make(dir)
	if err != nil {
		return Result{}, fmt.Errorf("sandbox setup: %w", err)
	}
	hooksDir := filepath.Join(dir, ".claude", "hooks")
	if err := os.MkdirAll(hooksDir, 0o755); err != nil {
		return Result{}, err
	}
	script := filepath.Join(hooksDir, "check-progress.ps1")
	if err := os.WriteFile(script, src, 0o644); err != nil {
		return Result{}, err
	}
	args := []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script}
	return runProcess(oracle, args, dir, env, timeout)
}

// runProcess runs a command with a timeout, capturing stdout and stderr
// SEPARATELY (they are different channels in the contract: block goes to
// stdout, notice to stderr — merging them would erase the distinction the
// comparison is about).
func runProcess(bin string, args []string, dir string, extraEnv []string, timeout time.Duration) (Result, error) {
	cmd := exec.Command(bin, args...)
	cmd.Dir = dir
	if len(extraEnv) > 0 {
		cmd.Env = append(os.Environ(), extraEnv...)
	}
	// WaitDelay bounds how long Wait blocks after the process is killed. Without
	// it, killing a shell script leaves its CHILD (e.g. `sleep`) holding the
	// stdout pipe, and Wait keeps blocking until that child exits — measured: a
	// 100ms timeout took 5s to return because the shim's `sleep 5` outlived it.
	// A timeout that does not actually bound the run is not a timeout.
	cmd.WaitDelay = 500 * time.Millisecond
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Start(); err != nil {
		return Result{}, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		res := Result{Stdout: stdout.String(), Stderr: stderr.String()}
		if err != nil {
			var ee *exec.ExitError
			if !errors.As(err, &ee) {
				return Result{}, err
			}
			res.Exit = ee.ExitCode()
			return res, nil
		}
		return res, nil
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		<-done
		return Result{}, fmt.Errorf("timed out after %s", timeout)
	}
}
