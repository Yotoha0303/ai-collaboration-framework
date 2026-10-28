package parallel

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// The four verdicts are the contract (a harness that cannot tell "checked" from
// "did not check" is the failure mode D3 is about). Each one gets a test, and
// the two that need a mismatch are driven with FAKE binaries — which is the
// point: the harness must be able to report DIFF, and that has to be provable
// without a PowerShell runtime.

func TestExitCodesDistinguishVerdicts(t *testing.T) {
	cases := []struct {
		kind RunKind
		want int
		str  string
	}{
		{KindPass, 0, "PASS"},
		{KindDiff, 1, "DIFF"},
		{KindSkip, 2, "SKIP"}, // NOT 0: skipping must not look like passing
		{KindError, 3, "ERROR"},
		{KindIncomplete, 4, "INCOMPLETE"}, // partial coverage; NOT 0 (GAP-051)
	}
	seen := map[int]bool{}
	for _, c := range cases {
		if got := c.kind.ExitCode(); got != c.want {
			t.Errorf("%v.ExitCode()=%d want %d", c.kind, got, c.want)
		}
		if got := c.kind.String(); got != c.str {
			t.Errorf("String()=%q want %q", got, c.str)
		}
		if seen[c.want] {
			t.Errorf("exit code %d is not unique", c.want)
		}
		seen[c.want] = true
	}
}

func TestRunErrorWhenBinaryMissing(t *testing.T) {
	rep := Run(Options{GuardBinary: filepath.Join(t.TempDir(), "nope")})
	if rep.Kind != KindError {
		t.Fatalf("Kind=%v want ERROR (missing binary)", rep.Kind)
	}
	if rep.Err == nil {
		t.Error("Err=nil want a message")
	}
	if rep.Kind.ExitCode() == 0 {
		t.Error("ERROR must not exit 0")
	}
}

func TestRunErrorWhenOracleWithoutScript(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
	rep := Run(Options{GuardBinary: bin, Oracle: "pwsh"}) // no LegacyScript
	if rep.Kind != KindError {
		t.Fatalf("Kind=%v want ERROR (oracle set, script unset)", rep.Kind)
	}
}

// TestRunSkipWithoutOracle is the headline behaviour on a machine without
// PowerShell: every scenario is reported SKIP, and the verdict is NOT PASS.
func TestRunSkipWithoutOracle(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
	rep := Run(Options{GuardBinary: bin, Scenarios: []Scenario{passthroughScenario()}})
	if rep.Kind != KindSkip {
		t.Fatalf("Kind=%v want SKIP (no oracle configured)", rep.Kind)
	}
	if rep.Kind.ExitCode() == KindPass.ExitCode() {
		t.Fatal("SKIP shares PASS's exit code; the two would be indistinguishable")
	}
	if len(rep.Comparisons) != 1 {
		t.Fatalf("len=%d want 1", len(rep.Comparisons))
	}
	if c := rep.Comparisons[0]; c.Comparable {
		t.Error("Comparable=true want false (nothing was compared)")
	}
}

// TestRunPassWithMatchingOracle: both sides behave identically → PASS.
func TestRunPassWithMatchingOracle(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
	sh := "#!/bin/sh\nexit 0\n"
	rep := Run(Options{
		GuardBinary:  bin,
		Oracle:       fakeBinNamed(t, "sh", sh),
		LegacyScript: fakeScript(t, sh),
		Scenarios:    []Scenario{passthroughScenario()},
	})
	if rep.Kind != KindPass {
		t.Fatalf("Kind=%v want PASS; comparisons=%v", rep.Kind, rep.Comparisons)
	}
	if !rep.Comparisons[0].Matches() {
		t.Error("Matches()=false want true")
	}
}

// TestRunDiffWithDivergingOracle: the two sides print different things → DIFF,
// and the report names both sides so a reader can see what diverged.
func TestRunDiffWithDivergingOracle(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\necho from-go\nexit 0\n")
	oracle := fakeBinNamed(t, "sh", "#!/bin/sh\necho from-ps1\nexit 0\n")
	rep := Run(Options{
		GuardBinary:  bin,
		Oracle:       oracle,
		LegacyScript: fakeScript(t, "#!/bin/sh\necho from-ps1\nexit 0\n"),
		Scenarios:    []Scenario{passthroughScenario()},
	})
	if rep.Kind != KindDiff {
		t.Fatalf("Kind=%v want DIFF", rep.Kind)
	}
	if rep.Kind.ExitCode() != 1 {
		t.Errorf("exit=%d want 1", rep.Kind.ExitCode())
	}
	sum := rep.Summary()
	for _, want := range []string{"DIFF", "from-go", "from-ps1"} {
		if !contains(sum, want) {
			t.Errorf("summary %q must contain %q", sum, want)
		}
	}
}

// TestRunExitCodeDifferenceDetected: a different EXIT CODE (same output) is also
// a diff — stdout alone is not the contract.
func TestRunExitCodeDifferenceDetected(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
	oracle := fakeBinNamed(t, "sh", "#!/bin/sh\nexit 1\n")
	rep := Run(Options{
		GuardBinary:  bin,
		Oracle:       oracle,
		LegacyScript: fakeScript(t, "#!/bin/sh\nexit 1\n"),
		Scenarios:    []Scenario{passthroughScenario()},
	})
	if rep.Kind != KindDiff {
		t.Fatalf("Kind=%v want DIFF (exit code differs)", rep.Kind)
	}
}

// TestRunExpectationViolationIsError: a Go side that contradicts its documented
// expectation is an ERROR, not a silent pass — the expectation is what makes a
// no-oracle run worth anything.
func TestRunExpectationViolationIsError(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n") // prints nothing
	sc := passthroughScenario()
	sc.Expect = Expect{Code: 0, StdoutContains: []string{"decision:block"}}
	rep := Run(Options{GuardBinary: bin, Scenarios: []Scenario{sc}})
	if rep.Kind != KindError {
		t.Fatalf("Kind=%v want ERROR (documented expectation violated)", rep.Kind)
	}
}

// TestRunContinuesAfterExpectationViolation is qa-validator P1-5.
//
// The original Run() did `return rep` the moment ONE scenario violated its
// Expect, so every scenario after it was never executed. The summary then said
// "N scenario(s)" with N = the number of scenarios reached, i.e. the harness
// reported a smaller run as if it were the run — a green-looking report that had
// silently stopped checking.
//
// The assertion is deliberately about the SECOND and THIRD scenarios being
// PROCESSED (present in the report), not merely about the verdict: a fix that
// still bailed out would produce a shorter Comparisons slice and fail here.
func TestRunContinuesAfterExpectationViolation(t *testing.T) {
	// The fake binary ignores its args and prints nothing, so the three scenarios
	// differ ONLY in their Expect. That is enough: "was scenario 3 processed" is
	// observable through the report's own per-scenario entries.
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")

	good := passthroughScenario()
	good.Name = "s1 good"

	bad := passthroughScenario()
	bad.Name = "s2 violates"
	bad.Expect = Expect{Code: 0, StdoutContains: []string{"never-printed"}}

	after := passthroughScenario()
	after.Name = "s3 after the violation"

	rep := Run(Options{GuardBinary: bin, Scenarios: []Scenario{good, bad, after}})

	if len(rep.Comparisons) != 3 {
		t.Fatalf("len(Comparisons)=%d want 3 — a violation must not abandon the remaining scenarios: %v",
			len(rep.Comparisons), rep.Comparisons)
	}
	if names := []string{rep.Comparisons[0].Name, rep.Comparisons[1].Name, rep.Comparisons[2].Name}; names[1] != "s2 violates" || names[2] != "s3 after the violation" {
		t.Errorf("order/identity changed: %v", names)
	}
	if rep.Comparisons[0].ExpectErr != "" {
		t.Errorf("s1 ExpectErr=%q want empty", rep.Comparisons[0].ExpectErr)
	}
	if rep.Comparisons[1].ExpectErr == "" {
		t.Error("s2 ExpectErr is empty — the violation was not recorded against its scenario")
	}
	if rep.Comparisons[2].ExpectErr != "" {
		t.Errorf("s3 ExpectErr=%q want empty (it was processed AFTER the violation)", rep.Comparisons[2].ExpectErr)
	}
	if rep.Kind != KindError {
		t.Errorf("Kind=%v want ERROR (a violation is never a pass)", rep.Kind)
	}
	if rep.Err != nil {
		t.Errorf("Err=%v want nil — an Expect violation is per-scenario, not fatal", rep.Err)
	}
}

// TestSummaryReportsComparedAndSkippedSeparately: the verdict line must expose
// COVERAGE. The old line printed one number (`%d scenario(s)` = len(Comparisons)),
// which made "all 15 skipped" and "all 15 compared" print the same size — the
// exact SKIP/PASS confusion the harness exists to prevent.
func TestSummaryReportsComparedAndSkippedSeparately(t *testing.T) {
	t.Run("all skipped, no oracle", func(t *testing.T) {
		bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
		rep := Run(Options{GuardBinary: bin, Scenarios: []Scenario{
			passthroughScenario(), passthroughScenario(), passthroughScenario(),
		}})
		sum := rep.Summary()
		for _, want := range []string{"COMPARED 0/3", "SKIPPED 3/3", "VERDICT SKIP"} {
			if !contains(sum, want) {
				t.Errorf("summary %q must contain %q", sum, want)
			}
		}
	})

	// NOTE (GAP-051): this subtest used to assert `VERDICT PASS` for a run that
	// compared 1 of 2 scenarios. That assertion WAS the defect — it encoded
	// "one comparison is enough" as the expected behaviour, which is why the
	// rule survived review. Partial coverage is INCOMPLETE, not PASS.
	t.Run("mixed: one compared, one gated → INCOMPLETE", func(t *testing.T) {
		bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
		gated := passthroughScenario()
		gated.Name = "gated"
		gated.SkipReason = func() string { return "test gate" }
		rep := Run(Options{
			GuardBinary:  bin,
			Oracle:       fakeBinNamed(t, "sh", "#!/bin/sh\nexit 0\n"),
			LegacyScript: fakeScript(t, "#!/bin/sh\nexit 0\n"),
			Scenarios:    []Scenario{passthroughScenario(), gated},
		})
		sum := rep.Summary()
		for _, want := range []string{"COMPARED 1/2", "SKIPPED 1/2", "VERDICT INCOMPLETE"} {
			if !contains(sum, want) {
				t.Errorf("summary %q must contain %q", sum, want)
			}
		}
		if contains(sum, "VERDICT PASS") {
			t.Errorf("summary claims PASS on 1/2 coverage: %q", sum)
		}
		if rep.Kind != KindIncomplete {
			t.Errorf("Kind=%v want INCOMPLETE", rep.Kind)
		}
		if got := rep.Kind.ExitCode(); got != 4 {
			t.Errorf("exit=%d want 4 (INCOMPLETE) — a partial run must not exit 0", got)
		}
	})

	t.Run("violations are counted and named", func(t *testing.T) {
		bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
		bad := passthroughScenario()
		bad.Name = "bad"
		bad.Expect = Expect{Code: 0, StdoutContains: []string{"never-printed"}}
		rep := Run(Options{GuardBinary: bin, Scenarios: []Scenario{bad, passthroughScenario()}})
		sum := rep.Summary()
		for _, want := range []string{"EXPECT bad", "EXPECT-VIOLATIONS 1/2", "VERDICT ERROR"} {
			if !contains(sum, want) {
				t.Errorf("summary %q must contain %q", sum, want)
			}
		}
	})

	t.Run("a diff never downgrades an expectation violation", func(t *testing.T) {
		// Go side prints nothing and violates its Expect; the oracle prints
		// differently, which would otherwise set DIFF. ERROR must win: the run
		// cannot be read as "equivalent but different".
		bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
		bad := passthroughScenario()
		bad.Expect = Expect{Code: 0, StdoutContains: []string{"never-printed"}}
		rep := Run(Options{
			GuardBinary:  bin,
			Oracle:       fakeBinNamed(t, "sh", "#!/bin/sh\necho other\n"),
			LegacyScript: fakeScript(t, "#!/bin/sh\necho other\n"),
			Scenarios:    []Scenario{bad},
		})
		if rep.Kind != KindError {
			t.Errorf("Kind=%v want ERROR (a DIFF must not mask a violated expectation)", rep.Kind)
		}
	})
}

// TestRunAllSkippedScenariosStaysSkip: an oracle that is configured but whose
// only scenario is platform-gated must NOT become PASS by defaulting.
func TestRunAllSkippedScenariosStaysSkip(t *testing.T) {
	bin := fakeBin(t, "#!/bin/sh\nexit 0\n")
	sc := passthroughScenario()
	sc.SkipReason = func() string { return "platform-gated for the test" }
	rep := Run(Options{
		GuardBinary:  bin,
		Oracle:       fakeBinNamed(t, "sh", "#!/bin/sh\nexit 0\n"),
		LegacyScript: fakeScript(t, "#!/bin/sh\nexit 0\n"),
		Scenarios:    []Scenario{sc},
	})
	if rep.Kind != KindSkip {
		t.Fatalf("Kind=%v want SKIP (nothing was compared)", rep.Kind)
	}
}

// TestFullCoverageRequiredForPass is GAP-051 / gate-auditor B8.
//
// The verdict rule used to be "at least ONE scenario was compared" (anyComparable),
// so a run that compared 1 of 15 and SKIPPED the other 14 still printed
// `VERDICT PASS` and exited 0 — and docs/changes/005 §7.6.4 read that exit=0 as
// the parity criterion. That is the D3 failure mode this harness exists to
// prevent (an empty denominator reported as 100%): coverage can collapse to one
// scenario and the gate stays green.
//
// The scenario COUNT is taken from the real Scenarios() list, not hardcoded, so
// this test keeps biting as that list grows.
func TestFullCoverageRequiredForPass(t *testing.T) {
	n := len(Scenarios())
	if n < 2 {
		t.Fatalf("len(Scenarios())=%d, need >=2 for this test to mean anything", n)
	}

	// synthetic mirrors the real list's names and length, but with
	// do-nothing fixtures so a fake binary can satisfy every Expect.
	synthetic := func() []Scenario {
		out := make([]Scenario, 0, n)
		for i, sc := range Scenarios() {
			s := passthroughScenario()
			s.Name = sc.Name
			if i > 0 {
				s.SkipReason = func() string { return "synthetic: oracle could not run here" }
			}
			out = append(out, s)
		}
		return out
	}

	t.Run("one comparable of N must not be PASS", func(t *testing.T) {
		rep := Run(Options{
			GuardBinary:  fakeBin(t, "#!/bin/sh\nexit 0\n"),
			Oracle:       fakeBinNamed(t, "sh", "#!/bin/sh\nexit 0\n"),
			LegacyScript: fakeScript(t, "#!/bin/sh\nexit 0\n"),
			Scenarios:    synthetic(),
		})
		if rep.Kind == KindPass {
			t.Errorf("Kind=PASS with only 1/%d scenarios compared — coverage collapsed and the gate stayed green", n)
		}
		if rep.Kind.ExitCode() == 0 {
			t.Errorf("exit=%d want non-zero: a partial run must not read as准出", rep.Kind.ExitCode())
		}
		sum := rep.Summary()
		if contains(sum, "VERDICT PASS") {
			t.Errorf("summary claims PASS on partial coverage:\n%s", sum)
		}
		if !contains(sum, fmt.Sprintf("COMPARED 1/%d", n)) {
			t.Errorf("summary must state the real coverage COMPARED 1/%d:\n%s", n, sum)
		}
	})

	t.Run("all comparable is still PASS with COMPARED N/N", func(t *testing.T) {
		scs := synthetic()
		for i := range scs {
			scs[i].SkipReason = nil
		}
		rep := Run(Options{
			GuardBinary:  fakeBin(t, "#!/bin/sh\nexit 0\n"),
			Oracle:       fakeBinNamed(t, "sh", "#!/bin/sh\nexit 0\n"),
			LegacyScript: fakeScript(t, "#!/bin/sh\nexit 0\n"),
			Scenarios:    scs,
		})
		if rep.Kind != KindPass {
			t.Fatalf("Kind=%v want PASS when every scenario was compared", rep.Kind)
		}
		want := fmt.Sprintf("COMPARED %d/%d", n, n)
		if sum := rep.Summary(); !contains(sum, want) {
			t.Errorf("summary must contain %q:\n%s", want, sum)
		}
	})

	t.Run("a PASS verdict line reads COMPARED N/N", func(t *testing.T) {
		// The invariant has to be readable from the report ALONE: a PASS that
		// does not carry full coverage in its verdict line is the defect itself.
		sum := Report{
			Kind:        KindPass,
			Comparisons: fullCoverageComparisons(Scenarios()),
		}.Summary()
		if last := lastLine(sum); !contains(last, fmt.Sprintf("COMPARED %d/%d", n, n)) {
			t.Errorf("PASS verdict line must read COMPARED %d/%d, got %q", n, n, last)
		}
	})
}

// TestRunTimeoutIsAnError: a hanging side must end as ERROR, not as a diff or a
// hang of the harness itself.
func TestRunTimeoutIsAnError(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("sleep shim is POSIX")
	}
	bin := fakeBin(t, "#!/bin/sh\nsleep 5\n")
	rep := Run(Options{
		GuardBinary: bin,
		Timeout:     100 * time.Millisecond,
		Scenarios:   []Scenario{passthroughScenario()},
	})
	if rep.Kind != KindError {
		t.Fatalf("Kind=%v want ERROR (timeout)", rep.Kind)
	}
}

// TestScenariosHaveUniqueNamesAndExpectations guards the list itself: duplicate
// names would make a report ambiguous, and a missing Expect (Code < 0) would
// make the no-oracle run assert nothing at all.
func TestScenariosHaveUniqueNamesAndExpectations(t *testing.T) {
	seen := map[string]bool{}
	for _, sc := range Scenarios() {
		if sc.Name == "" {
			t.Error("unnamed scenario")
		}
		if seen[sc.Name] {
			t.Errorf("duplicate scenario name %q", sc.Name)
		}
		seen[sc.Name] = true
		if sc.Expect.Code < 0 {
			t.Errorf("scenario %q has no Expect.Code", sc.Name)
		}
		if sc.Make == nil {
			t.Errorf("scenario %q has no Make", sc.Name)
		}
	}
}

// TestFixtureSurvivesHostileHostGitConfig is qa-validator P2-6.
//
// The harness builds two sandboxes from one recipe and compares bytes. If the
// recipe's output depends on the HOST's git configuration, the two builds can
// differ for reasons that say nothing about the port — a "DIFF" that is pure
// noise, or (worse) a scenario that never runs. Two host settings were measured
// to do exactly that (2026-10-28):
//
//   - commit.gpgsign=true in the global config: `git commit` exits 128, so every
//     scenario becomes ERROR;
//   - GIT_DEFAULT_HASH=sha256 (or init.defaultObjectFormat): ids become 64-hex
//     and `--short` yields EIGHT characters, which the page regex ({7,40}) and
//     the Go side's 40-hex fullIDRe were never designed for — the two sides
//     would then disagree about whether an id even resolves.
//
// This test sets both, then asserts the fixture comes out sha1 / 7-char / 40-char
// anyway. It is a test of the RECIPE (initRepoOnMain), not of git, so it fails
// the moment someone drops the `--object-format` pin or the `-c` flags.
func TestFixtureSurvivesHostileHostGitConfig(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the hostile config names /bin/false as the signing program")
	}
	hostile := filepath.Join(t.TempDir(), "hostile.gitconfig")
	body := "[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /bin/false\n[user]\n\tsigningkey = DEADBEEF\n"
	if err := os.WriteFile(hostile, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_CONFIG_GLOBAL", hostile)
	t.Setenv("GIT_DEFAULT_HASH", "sha256")

	dir := t.TempDir()
	if err := initRepoOnMain(dir); err != nil {
		t.Fatalf("fixture must survive a hostile host git config: %v", err)
	}

	if got := strings.TrimSpace(fixtureGit(t, dir, "rev-parse", "--show-object-format")); got != "sha1" {
		t.Errorf("object format=%q want sha1 (sha256 gives 8-char short ids and 64-hex ids)", got)
	}
	full := strings.TrimSpace(fixtureGit(t, dir, "rev-parse", "HEAD"))
	if len(full) != 40 {
		t.Errorf("full id %q has len %d want 40 (sha/id the guard's regexes assume)", full, len(full))
	}
	short, err := shortHead(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(short) != 7 {
		t.Errorf("short id %q has len %d want 7", short, len(short))
	}
}

// TestFixtureCommitsAreDeterministic pins the reason the dates are fixed: the
// same recipe must produce the SAME id twice, or the two sandboxes cannot be
// compared byte for byte (the reason string embeds the short id).
func TestFixtureCommitsAreDeterministic(t *testing.T) {
	a, b := t.TempDir(), t.TempDir()
	for _, d := range []string{a, b} {
		if err := initRepoOnMain(d); err != nil {
			t.Fatal(err)
		}
	}
	ha := strings.TrimSpace(fixtureGit(t, a, "rev-parse", "HEAD"))
	hb := strings.TrimSpace(fixtureGit(t, b, "rev-parse", "HEAD"))
	if ha != hb {
		t.Errorf("same recipe produced different ids:\n  a=%s\n  b=%s", ha, hb)
	}
}

// fixtureGit runs a read-only git command in a fixture repo, WITHOUT the signing
// overrides — reading does not sign, and going through the plain command keeps
// this helper independent of the code under test.
func fixtureGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	c := exec.Command("git", append([]string{"-C", dir}, args...)...)
	c.Env = append(os.Environ(), "GIT_AUTHOR_DATE="+fixtureDate, "GIT_COMMITTER_DATE="+fixtureDate)
	out, err := c.Output()
	if err != nil {
		t.Fatalf("git %v in %s: %v", args, dir, err)
	}
	return string(out)
}

// --- helpers ---

// passthroughScenario does nothing to the sandbox and asserts nothing, so it is
// usable with fake binaries that ignore their arguments.
func passthroughScenario() Scenario {
	return Scenario{
		Name:   "synthetic",
		Make:   func(string) ([]string, error) { return nil, nil },
		Expect: Expect{Code: 0},
	}
}

// fakeBin writes an executable sh script and returns its path.
func fakeBin(t *testing.T, body string) string {
	t.Helper()
	return fakeBinNamed(t, "bin", body)
}

func fakeBinNamed(t *testing.T, name, body string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("POSIX sh fake binaries; the Windows shape is not measured")
	}
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

// fakeScript writes a file to stand in for check-progress.ps1 (its CONTENT is
// irrelevant: the fake oracle ignores its arguments).
func fakeScript(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "check-progress.ps1")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// fullCoverageComparisons turns a scenario list into comparisons that all
// happened and all matched — the only shape a PASS may be built from.
func fullCoverageComparisons(scs []Scenario) []Comparison {
	out := make([]Comparison, 0, len(scs))
	for _, sc := range scs {
		out = append(out, Comparison{
			Name:       sc.Name,
			Go:         Result{Exit: 0},
			Oracle:     Result{Exit: 0},
			Comparable: true,
		})
	}
	return out
}

// lastLine returns the final line of a summary (the verdict line).
func lastLine(s string) string {
	s = strings.TrimRight(s, "\n")
	if i := strings.LastIndex(s, "\n"); i >= 0 {
		return s[i+1:]
	}
	return s
}

func contains(haystack, needle string) bool { return strings.Contains(haystack, needle) }
