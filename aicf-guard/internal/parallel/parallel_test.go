package parallel

import (
	"os"
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

func contains(haystack, needle string) bool { return strings.Contains(haystack, needle) }
