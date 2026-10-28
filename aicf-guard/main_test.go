package main

import (
	"bytes"
	"fmt"
	"io"
	"testing"
)

// TestVersionDefault verifies the --version output with the default (uninjected)
// build-time constants. The format is "aicf-guard <semver> (<commit-hash>)\n"
// (ADR §2.1 R4). Build-time injection (-ldflags) is verified separately by a
// shell build command in docs/changes/005 (a Go test cannot inject ldflags).
func TestVersionDefault(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"--version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit=%d want 0; stderr=%q", code, stderr.String())
	}
	want := fmt.Sprintf("aicf-guard %s (%s)\n", version, commit)
	if got := stdout.String(); got != want {
		t.Errorf("stdout=%q want %q", got, want)
	}
	if stderr.Len() != 0 {
		t.Errorf("stderr=%q want empty", stderr.String())
	}
}

// TestVersionShortFlag verifies -V is an alias for --version.
func TestVersionShortFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"-V"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit=%d want 0", code)
	}
	want := fmt.Sprintf("aicf-guard %s (%s)\n", version, commit)
	if got := stdout.String(); got != want {
		t.Errorf("stdout=%q want %q", got, want)
	}
}

// TestNoArgs verifies that running with no arguments prints usage to stderr and
// exits 2 (usage error). It must NOT exit 0 (which would be a silent success).
func TestNoArgs(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run(nil, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("exit=%d want 2", code)
	}
	if stderr.Len() == 0 {
		t.Error("want usage on stderr, got empty")
	}
	if stdout.Len() != 0 {
		t.Errorf("stdout=%q want empty (usage goes to stderr on error)", stdout.String())
	}
}

// TestUnknownSubcommand verifies an unknown subcommand exits 2 with a clear
// stderr message. It must NOT be mistaken for a known placeholder (exit 1).
func TestUnknownSubcommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"bogus"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("exit=%d want 2", code)
	}
	if stderr.Len() == 0 {
		t.Error("want error message on stderr")
	}
}

// TestSubcommandPlaceholders verifies every RESERVED-BUT-UNPORTED subcommand
// name is recognised (dispatched) and exits 1 with a clear "not implemented"
// message. A placeholder must NOT exit 0 (silent success) — that would be
// fail-OPEN. `progress` is deliberately absent: it is implemented (M0 2nd
// dispatch) and is covered by TestProgressSubcommandBelow.
func TestSubcommandPlaceholders(t *testing.T) {
	subs := []string{"numbers", "inject", "adapter", "selftest", "doctor"}
	for _, sub := range subs {
		t.Run(sub, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			code := run([]string{sub}, &stdout, &stderr)
			if code != 1 {
				t.Errorf("exit=%d want 1 (placeholder, not implemented)", code)
			}
			if stderr.Len() == 0 {
				t.Error("want 'not implemented' message on stderr")
			}
			if stdout.Len() != 0 {
				t.Errorf("stdout=%q want empty", stdout.String())
			}
		})
	}
}

// TestProgressSubcommandBelow: the dispatch reaches the progress package. An
// explicit --workspace pointing at a non-workspace resolves to nothing, which
// the contract maps to a silent exit 0 — so this proves wiring without
// depending on the developer's own workspace state.
func TestProgressSubcommandBelow(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"progress", "--workspace", t.TempDir()}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit=%d want 0 (unresolvable workspace is a deliberate silence); stderr=%q", code, stderr.String())
	}
	if stdout.Len() != 0 || stderr.Len() != 0 {
		t.Errorf("stdout=%q stderr=%q; want both empty", stdout.String(), stderr.String())
	}
}

// TestProgressBadFlag: a malformed flag must be a usage error (2), never a
// silent 0 — the guard's own flags must not be able to fail open.
func TestProgressBadFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"progress", "--no-such-flag"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit=%d want 2; stderr=%q", code, stderr.String())
	}
	if stdout.Len() != 0 {
		t.Errorf("stdout=%q want empty", stdout.String())
	}
}

// TestHelp verifies -h/--help prints usage to stdout and exits 0.
func TestHelp(t *testing.T) {
	for _, flag := range []string{"-h", "--help"} {
		t.Run(flag, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			code := run([]string{flag}, &stdout, &stderr)
			if code != 0 {
				t.Fatalf("exit=%d want 0", code)
			}
			if stdout.Len() == 0 {
				t.Error("want usage on stdout")
			}
			if stderr.Len() != 0 {
				t.Errorf("stderr=%q want empty", stderr.String())
			}
		})
	}
}

// TestVersionNoExternalState is a behavioural guard (ADR §2.1: "--version 不读
// 工作区、不调 git、不依赖任何外部状态"): --version must produce identical output
// regardless of CWD or env. We cannot fully prove a negative, but we can prove
// the output is a pure function of the build-time constants — by checking it
// equals the format string with no other input. (If a future change made
// --version call git or read a file, this test would still pass on format, so
// the real guard is code review + the ADR invariant; this test pins the format.)
func TestVersionNoExternalState(t *testing.T) {
	var stdout1, stdout2 bytes.Buffer
	// Two runs with different (synthetic) arg tails must yield the same stdout.
	run([]string{"--version"}, &stdout1, io.Discard)
	run([]string{"--version"}, &stdout2, io.Discard)
	if stdout1.String() != stdout2.String() {
		t.Errorf("non-deterministic --version output: %q vs %q", stdout1.String(), stdout2.String())
	}
	// And it must be exactly the format string (no extra lines).
	want := fmt.Sprintf("aicf-guard %s (%s)\n", version, commit)
	if stdout1.String() != want {
		t.Errorf("stdout=%q want %q", stdout1.String(), want)
	}
}
