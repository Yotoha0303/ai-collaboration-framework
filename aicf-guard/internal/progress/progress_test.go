package progress

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"aicf-guard/internal/git"
	"aicf-guard/internal/mainline"
	"aicf-guard/internal/page"
	"aicf-guard/internal/sha"
	"aicf-guard/internal/workspace"
)

// The branch contract (docs/changes/005 §4.2.2, ADR-001 §1.2) has eleven
// branches. Each one gets a test that drives it in isolation through synthetic
// Deps — including the two NOTICE branches, which cannot be reached against a
// working git and would otherwise never be exercised anywhere. Then
// TestRunSandbox* runs the same code against a real temp repo with the real
// shared libraries, so the wiring is covered too (a unit test of the branches
// plus an unreached production wiring is the classic "green tests, dead code").

const (
	fullA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	fullB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// --- P1: workspace unresolvable → silent ---

func TestRunP1WorkspaceUnresolved(t *testing.T) {
	d := stubDeps()
	d.Resolve = func(string) workspace.Result { return workspace.Result{} }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P1 workspace unresolved", code, out, errOut)
}

// --- P2: pointer fault → exit 1 + stderr (and it outranks "no page") ---

func TestRunP2PointerFault(t *testing.T) {
	d := stubDeps()
	d.ReadPageName = func(string) page.NameResult {
		return page.NameResult{Name: page.DefaultPageName, Fault: true}
	}
	// No page exists either — the fault must still be reported (224-227 before 233).
	d.FindPage = func(string, string) (string, bool) { return "", false }
	code, out, errOut := runOnce(t, nil, d)

	if code != 1 {
		t.Errorf("exit=%d want 1 (pointer fault is a notice)", code)
	}
	if out != "" {
		t.Errorf("stdout=%q want empty", out)
	}
	if errOut != msgPointerFault+"\n" {
		t.Errorf("stderr=%q want %q", errOut, msgPointerFault+"\n")
	}
}

// TestRunP2PointerFaultOutranksNoPage is the ordering guard: with a fault AND no
// page, a branch reordering would turn this into a silent exit 0.
func TestRunP2PointerFaultOutranksNoPage(t *testing.T) {
	d := stubDeps()
	d.ReadPageName = func(string) page.NameResult { return page.NameResult{Name: "x.html", Fault: true} }
	d.FindPage = func(string, string) (string, bool) { return "/tmp/whatever", true }
	code, _, errOut := runOnce(t, nil, d)
	if code != 1 || errOut == "" {
		t.Errorf("exit=%d stderr=%q; want 1 + notice", code, errOut)
	}
}

// --- P3: no page → silent (and git is NEVER consulted) ---

func TestRunP3NoPage(t *testing.T) {
	d := stubDeps()
	d.FindPage = func(string, string) (string, bool) { return "", false }
	called := false
	d.Probe = func() bool { called = true; return true }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P3 no page", code, out, errOut)
	if called {
		t.Error("Probe was called on the no-page branch; the .ps1 exits before touching git (233 precedes 246)")
	}
}

// --- P4: git unusable → exit 1 + stderr ---

func TestRunP4GitUnusable(t *testing.T) {
	d := stubDeps()
	d.Probe = func() bool { return false }
	code, out, errOut := runOnce(t, nil, d)

	if code != 1 {
		t.Errorf("exit=%d want 1 (missing git is a notice, not silence and not block)", code)
	}
	if out != "" {
		t.Errorf("stdout=%q want empty", out)
	}
	if errOut != msgGitUnusable+"\n" {
		t.Errorf("stderr=%q want %q", errOut, msgGitUnusable+"\n")
	}
}

// --- P5: canary untrustworthy → exit 1 + stderr ---

func TestRunP5CanaryUntrustworthy(t *testing.T) {
	d := stubDeps()
	d.Canary = func() bool { return false }
	code, out, errOut := runOnce(t, nil, d)

	if code != 1 {
		t.Errorf("exit=%d want 1", code)
	}
	if out != "" {
		t.Errorf("stdout=%q want empty", out)
	}
	if errOut != msgCanaryFailed+"\n" {
		t.Errorf("stderr=%q want %q", errOut, msgCanaryFailed+"\n")
	}
}

// --- P6: no repo candidate → silent ---

func TestRunP6NoRepo(t *testing.T) {
	d := stubDeps()
	d.Resolve = func(string) workspace.Result {
		return workspace.Result{Workspace: "/ws", Repo: "", Ok: false}
	}
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P6 no repo", code, out, errOut)
}

// noRepoMismatchDeps walks the happy path but makes the page MISMATCH the
// mainline, and makes every later step resolvable. Removing the repo/mainline
// silent branch then turns the run into a block — which is what these tests
// assert must NOT happen.
func noRepoMismatchDeps() Deps {
	d := stubDeps()
	d.Mainline = func(string) mainline.Result {
		return mainline.Result{Ref: "HEAD", Name: "HEAD", Ok: true}
	}
	d.ResolveFull = func(repo, id string) (string, bool) {
		if id == "HEAD" {
			return fullA, true
		}
		return fullB, true // the recorded id resolves to a DIFFERENT commit
	}
	d.ReadHead = func(string) (string, bool) { return fullB[:7], true }
	return d
}

// TestRunP6NoRepoIgnoresMainline: the repo check must be a DECISION, not a
// precondition that happens to fail later.
func TestRunP6NoRepoIgnoresMainline(t *testing.T) {
	d := noRepoMismatchDeps()
	d.Resolve = func(string) workspace.Result {
		return workspace.Result{Workspace: "/ws", Repo: "", Ok: false}
	}
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P6 no repo (everything else would block)", code, out, errOut)
}

// --- P7: mainline unresolvable (unborn) → silent ---

func TestRunP7MainlineUnresolved(t *testing.T) {
	d := stubDeps()
	d.Mainline = func(string) mainline.Result { return mainline.Result{} }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P7 unborn / no mainline", code, out, errOut)
}

// TestRunP7MainlineUnresolvedIsHonoured: an unresolvable mainline must be
// SILENT even though everything downstream would happily resolve and block.
// Otherwise a caller that re-derived a fallback ref would turn "unborn repo"
// into a block at onboarding time — the noise GAP-012 recorded.
func TestRunP7MainlineUnresolvedIsHonoured(t *testing.T) {
	d := noRepoMismatchDeps()
	d.Mainline = func(string) mainline.Result { return mainline.Result{} }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P7 mainline unresolved (everything else would block)", code, out, errOut)
}

// TestRunShortRefFailureFallsBackToFullID: the short form is only wording. If
// `rev-parse --short` fails, the reason must still name a commit — the FULL id
// (check-progress.ps1:350). An empty slot would produce `而 main 是 。`.
func TestRunShortRefFailureFallsBackToFullID(t *testing.T) {
	d := stubDeps()
	d.ShortRef = func(string, string) (string, bool) { return "", false }
	d.ResolveFull = func(repo, id string) (string, bool) {
		switch id {
		case "refs/heads/main":
			return fullA, true
		case "deadbee":
			return fullB, true
		}
		return "", false
	}
	code, out, _ := runOnce(t, nil, d)
	if code != 0 || !strings.Contains(out, "是 "+fullA+"。") {
		t.Errorf("exit=%d stdout=%q; want the FULL id in the `是 …。` slot when --short fails", code, out)
	}
}

// --- P8: mainline full id does not resolve → silent ---

func TestRunP8MainlineFullIDFails(t *testing.T) {
	d := stubDeps()
	d.ResolveFull = func(repo, id string) (string, bool) { return "", false }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P8 mainline full id fails", code, out, errOut)
}

// --- P9: page has no marker → silent (GAP-025 residual) ---

func TestRunP9NoHeadMarker(t *testing.T) {
	d := stubDeps()
	d.ReadHead = func(string) (string, bool) { return "", false }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P9 no head marker", code, out, errOut)
}

// --- P10: mismatch → block ---

func TestRunP10BlockOnMismatch(t *testing.T) {
	d := stubDeps()
	d.ResolveFull = func(repo, id string) (string, bool) {
		switch id {
		case "refs/heads/main":
			return fullA, true
		case "deadbee": // the recorded id
			return fullB, true
		}
		return "", false
	}
	code, out, errOut := runOnce(t, nil, d)

	if code != 0 {
		t.Errorf("exit=%d want 0 (block is a decision, not an error)", code)
	}
	if errOut != "" {
		t.Errorf("stderr=%q want empty", errOut)
	}

	// Exactly one compressed line, parseable as the documented shape.
	if !strings.HasSuffix(out, "\n") || strings.Count(out, "\n") != 1 {
		t.Fatalf("stdout=%q want exactly one line", out)
	}
	var got struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatalf("stdout is not JSON: %v (%q)", err, out)
	}
	if got.Decision != "block" {
		t.Errorf("decision=%q want block", got.Decision)
	}
	// The reason must name the compared line AND the two SHAs (GAP-031).
	for _, want := range []string{"main", "deadbee", "abcdef1"} {
		if !strings.Contains(got.Reason, want) {
			t.Errorf("reason %q must contain %q", got.Reason, want)
		}
	}
}

// TestRunP10RecordedIDUnresolvable: the recorded id failing to resolve is a
// LAGGING page, not a reason to fall silent (GAP-008 / the V13 case).
func TestRunP10RecordedIDUnresolvable(t *testing.T) {
	d := stubDeps()
	d.ResolveFull = func(repo, id string) (string, bool) {
		if id == "refs/heads/main" {
			return fullA, true
		}
		return "", false // the recorded id does not resolve
	}
	code, out, errOut := runOnce(t, nil, d)
	if code != 0 || !strings.Contains(out, `"decision":"block"`) || errOut != "" {
		t.Errorf("exit=%d stdout=%q stderr=%q; want block on stdout", code, out, errOut)
	}
}

// --- P11: equal → silent ---

func TestRunP11InSync(t *testing.T) {
	d := stubDeps()
	d.ResolveFull = func(repo, id string) (string, bool) { return fullA, true }
	code, out, errOut := runOnce(t, nil, d)
	wantSilent(t, "P11 in sync", code, out, errOut)
}

// --- the reason string, byte for byte ---

// TestReasonStringMatchesPS1 pins the message. The .ps1's wording is a
// published contract (the model reads the reason and acts on it), and the four
// interpolations must appear in the same places.
func TestReasonStringMatchesPS1(t *testing.T) {
	got := sprintfReason("page.html", "deadbee", "origin/main", "abcdef1")
	want := "进度页落后于主干：page.html 记录的 HEAD 是 deadbee，而 origin/main 是 abcdef1。" +
		"请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。" +
		"需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"
	if got != want {
		t.Errorf("reason mismatch\n got: %q\nwant: %q", got, want)
	}
}

// TestBlockJSONShapeNoHTMLEscaping: Go's default encoder would escape <, > and &
// (→ < …), which ConvertTo-Json does not. A reason containing them must
// still come out byte-identical in spirit.
func TestBlockJSONShapeNoHTMLEscaping(t *testing.T) {
	var buf bytes.Buffer
	if err := writeDecisionBlock(&buf, "a <b> & c"); err != nil {
		t.Fatal(err)
	}
	want := `{"decision":"block","reason":"a <b> & c"}` + "\n"
	if buf.String() != want {
		t.Errorf("got %q want %q", buf.String(), want)
	}
}

// --- flags ---

// TestRunUsageErrorsExitOne pins the {0,1}-only contract for THIS subcommand.
//
// qa-validator P1-1 (docs/changes/005 §十): these three cases used to return 2.
// That looked like "loud usage error" but was in fact a SILENT ALLOW — the hosts
// that run this hook do not define 2 as a failure (stop-adapter.ps1:56-74 falls
// through to `allow`), so a typo'd flag retired the guard without a word.
//
// The assertions are deliberately threefold so a future edit cannot satisfy the
// letter while losing the teeth: exit 1 (not 0, not 2), stdout EMPTY (a usage
// error must never emit a decision:block), stderr NAMES the problem as a usage
// error AND says the guard did not run.
func TestRunUsageErrorsExitOne(t *testing.T) {
	cases := []struct {
		name string
		args []string
	}{
		{"unknown flag", []string{"--bogus"}},
		{"missing flag value", []string{"--workspace"}},
		{"stray positional", []string{"--workspace", "/ws", "extra"}},
		{"positional only", []string{"extra"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := stubDeps()
			// If a usage error ever reached decide(), this would make the run look
			// like a silent allow (Resolve → empty → exit 0) and the assertion
			// below would catch it as exit 0 instead of 1.
			d.Resolve = func(string) workspace.Result { return workspace.Result{} }
			code, out, errOut := runOnce(t, c.args, d)

			if code != 1 {
				t.Errorf("exit=%d want 1 (usage error takes the notice channel; 2 is UNREADABLE by the hosts)", code)
			}
			if out != "" {
				t.Errorf("stdout=%q want empty (usage errors must not emit a decision)", out)
			}
			if !strings.Contains(errOut, "usage error") {
				t.Errorf("stderr=%q must say it was a usage error", errOut)
			}
			if !strings.Contains(errOut, "did NOT run") {
				t.Errorf("stderr=%q must say the guard did not run", errOut)
			}
		})
	}
}

// TestRunNeverReturnsTwo enumerates every invocation CLASS this subcommand can
// see and asserts none yields 2. Enumerating the classes (rather than trusting
// the four cases above) is what makes "no path returns 2" checkable at all: the
// original defect was one forgotten `return 2`, and there were two of them.
//
// Keep this list in sync with Run's branches: a new exit path must be added
// here, and the assertion will fail the moment one of them answers 2.
func TestRunNeverReturnsTwo(t *testing.T) {
	cases := []struct {
		name string
		args []string
		mut  func(*Deps)
	}{
		{"help long", []string{"--help"}, nil},
		{"help short", []string{"-h"}, nil},
		{"unknown flag", []string{"--bogus"}, nil},
		{"missing value", []string{"--workspace"}, nil},
		{"stray positional", []string{"stray"}, nil},
		{"silent allow (workspace unresolved, discovery)", nil, func(d *Deps) {
			d.Resolve = func(string) workspace.Result { return workspace.Result{} }
		}},
		{"notice (pointer fault)", nil, func(d *Deps) {
			d.ReadPageName = func(string) page.NameResult { return page.NameResult{Fault: true, Name: page.DefaultPageName} }
		}},
		{"notice (git unusable)", nil, func(d *Deps) { d.Probe = func() bool { return false } }},
		{"block", nil, func(d *Deps) {
			d.ReadHead = func(string) (string, bool) { return "0000000", true }
			d.ResolveFull = func(repo, id string) (string, bool) {
				if id == "refs/heads/main" {
					return fullA, true
				}
				return "", false
			}
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := stubDeps()
			if c.mut != nil {
				c.mut(&d)
			}
			code, _, errOut := runOnce(t, c.args, d)
			if code == 2 {
				t.Fatalf("exit=2 (stderr=%q): the hosts read 2 as ALLOW — the guard would be silently dead", errOut)
			}
			if code != 0 && code != 1 {
				t.Errorf("exit=%d outside the published contract {0,1} (ADR-001 §1.2)", code)
			}
		})
	}
}

func TestRunHelpExitsZero(t *testing.T) {
	d := stubDeps()
	code, _, errOut := runOnce(t, []string{"--help"}, d)
	if code != 0 {
		t.Errorf("exit=%d want 0 (asking for help is not an error)", code)
	}
	if !strings.Contains(errOut, "usage: aicf-guard progress") {
		t.Errorf("stderr=%q want usage text", errOut)
	}
}

// TestRunWorkspaceFlagReachesResolve: --workspace must be handed to Resolve,
// not silently ignored (ADR §2.1: selftest sandbox and unit tests depend on it).
func TestRunWorkspaceFlagReachesResolve(t *testing.T) {
	d := stubDeps()
	var seen string
	d.Resolve = func(flag string) workspace.Result {
		seen = flag
		return workspace.Result{} // stop immediately
	}
	runOnce(t, []string{"--workspace", "/explicit/ws"}, d)
	if seen != "/explicit/ws" {
		t.Errorf("Resolve received %q want /explicit/ws", seen)
	}
}

// --- end to end against a real repo, real shared libraries ---

// TestRunSandboxBranches drives the PRODUCTION wiring (DefaultDeps) in a temp
// workspace + repo. The synthetic tests above prove the branch logic; this one
// proves the wiring, which the branch tests cannot (they replace every
// collaborator).
func TestRunSandboxBranches(t *testing.T) {
	sb := newSandbox(t)
	head := sb.head(t)

	t.Run("A2 in-sync is silent", func(t *testing.T) {
		sb.writePage(t, "<html><body><div>head <b>"+head[:7]+"</b></div></body></html>")
		code, out, errOut := runReal(t, sb.dir)
		wantSilent(t, "in sync", code, out, errOut)
	})

	t.Run("A1 stale page blocks and names the mainline", func(t *testing.T) {
		sb.writePage(t, "<html><body><div>head <b>0000000</b></div></body></html>")
		code, out, errOut := runReal(t, sb.dir)
		if code != 0 || errOut != "" {
			t.Fatalf("exit=%d stderr=%q; want 0 + block on stdout", code, errOut)
		}
		var got struct {
			Decision string `json:"decision"`
			Reason   string `json:"reason"`
		}
		if err := json.Unmarshal([]byte(out), &got); err != nil {
			t.Fatalf("stdout not JSON: %v (%q)", err, out)
		}
		if got.Decision != "block" {
			t.Errorf("decision=%q want block", got.Decision)
		}
		if !strings.Contains(got.Reason, "main") || !strings.Contains(got.Reason, "0000000") {
			t.Errorf("reason %q must name the mainline and the recorded SHA", got.Reason)
		}
		// The SHORT form specifically — not the full id. `是 <short>。` is the
		// exact slot; a full id would also "contain" the short prefix, so the
		// assertion has to be anchored on the punctuation to have teeth.
		if !strings.Contains(got.Reason, "是 "+head[:7]+"。") {
			t.Errorf("reason %q must name the SHORT mainline SHA %q in the `是 …。` slot", got.Reason, head[:7])
		}
	})

	t.Run("A4 <b class> still blocks (GAP-025 fixed cell)", func(t *testing.T) {
		sb.writePage(t, `<div>head <b class="v">0000000</b></div>`)
		code, out, _ := runReal(t, sb.dir)
		if code != 0 || !strings.Contains(out, `"decision":"block"`) {
			t.Errorf("exit=%d stdout=%q; want block", code, out)
		}
	})

	t.Run("A5 <span> restructure is silent (GAP-025 residual, pinned)", func(t *testing.T) {
		sb.writePage(t, `<div>head <span>0000000</span></div>`)
		code, out, errOut := runReal(t, sb.dir)
		wantSilent(t, "span residual", code, out, errOut)
	})

	t.Run("A3 pointer names a missing page is silent (GAP-002 accepted cost)", func(t *testing.T) {
		sb.writePage(t, `<div>head <b>0000000</b></div>`)
		sb.writePointer(t, "no-such-page.html\n")
		code, out, errOut := runReal(t, sb.dir)
		wantSilent(t, "pointer to missing page", code, out, errOut)
		sb.writePointer(t, "project-progress.html\n")
	})

	t.Run("P2 empty pointer is a notice", func(t *testing.T) {
		sb.writePointer(t, "   \n")
		code, out, errOut := runReal(t, sb.dir)
		if code != 1 || out != "" || errOut != msgPointerFault+"\n" {
			t.Errorf("exit=%d stdout=%q stderr=%q; want 1 + the pointer-fault notice", code, out, errOut)
		}
		sb.writePointer(t, "project-progress.html\n")
	})

	t.Run("P3 no page at all is silent", func(t *testing.T) {
		if err := os.Remove(filepath.Join(sb.dir, "project-progress.html")); err != nil {
			t.Fatal(err)
		}
		code, out, errOut := runReal(t, sb.dir)
		wantSilent(t, "no page", code, out, errOut)
	})
}

// TestRunSandboxFeatureBranchComparesMainline is the GAP-031 regression guard at
// the subprocess-free level: on a feature branch whose tip differs from the
// trunk, a page recording the TRUNK must be silent, and a page recording the
// BRANCH TIP must block. (The .ps1's A12/A13 cells, reproduced against the real
// libraries.)
func TestRunSandboxFeatureBranchComparesMainline(t *testing.T) {
	sb := newSandbox(t)
	mainHead := sb.head(t)

	sb.git(t, "checkout", "-q", "-b", "feature")
	sb.commitEmpty(t, "feature work")
	branchHead := sb.head(t)
	if branchHead == mainHead {
		t.Fatal("setup: feature tip equals main; the cell would prove nothing")
	}

	// Page records the TRUNK → must be silent (before GAP-031 this false-alarmed).
	sb.writePage(t, "<div>head <b>"+mainHead[:7]+"</b></div>")
	if code, out, errOut := runReal(t, sb.dir); code != 0 || out != "" || errOut != "" {
		t.Errorf("trunk-recorded page on a feature branch: exit=%d stdout=%q stderr=%q; want silence (GAP-031)", code, out, errOut)
	}

	// Page records the BRANCH TIP → must block (it resolves, but is not the trunk).
	sb.writePage(t, "<div>head <b>"+branchHead[:7]+"</b></div>")
	code, out, errOut := runReal(t, sb.dir)
	if code != 0 || errOut != "" || !strings.Contains(out, `"decision":"block"`) {
		t.Fatalf("branch-tip-recorded page: exit=%d stdout=%q stderr=%q; want block (A13)", code, out, errOut)
	}
	if !strings.Contains(out, "而 main 是") {
		t.Errorf("reason must name the mainline it compared against; got %q", out)
	}
}

// TestRunSandboxUnbornRepoIsSilent: a repo with no commit at all (fresh init)
// has no mainline concept; the guard must not alert at onboarding time.
func TestRunSandboxUnbornRepoIsSilent(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	mustGit(t, dir, "init", "-q")
	if err := os.WriteFile(filepath.Join(dir, "project-progress.html"), []byte("<div>head <b>0000000</b></div>"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runReal(t, dir)
	wantSilent(t, "unborn repo", code, out, errOut)
}

// TestRunSandboxNoRepoIsSilent: a workspace with `.claude/` but no repo.
func TestRunSandboxNoRepoIsSilent(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "project-progress.html"), []byte("<div>head <b>0000000</b></div>"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runReal(t, dir)
	wantSilent(t, "no repo", code, out, errOut)
}

// TestRunSandboxProjectChildLayout: the target layout — the workspace root has
// no `.git`, the repo is a `project/` child.
func TestRunSandboxProjectChildLayout(t *testing.T) {
	ws := t.TempDir()
	if err := os.MkdirAll(filepath.Join(ws, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	repo := filepath.Join(ws, "project")
	if err := os.MkdirAll(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	mustGit(t, repo, "init", "-q")
	mustGit(t, repo, "config", "user.email", "test@example.com")
	mustGit(t, repo, "config", "user.name", "Test")
	mustGit(t, repo, "symbolic-ref", "HEAD", "refs/heads/main")
	mustGit(t, repo, "commit", "-q", "--allow-empty", "-m", "seed")
	head := strings.TrimSpace(runGit(t, repo, "rev-parse", "HEAD"))

	if err := os.WriteFile(filepath.Join(ws, "project-progress.html"),
		[]byte("<div>head <b>"+head[:7]+"</b></div>"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runReal(t, ws)
	wantSilent(t, "project/ child layout, page in sync", code, out, errOut)
}

// TestRunSandboxGitUnavailableNotice: the production wiring's notice branch,
// reached with the real libs by putting a non-executable `git` first on PATH.
//
// On Windows the shim shape differs (no shebang), so this is POSIX-only; the
// synthetic P4 test above covers the branch portably.
func TestRunSandboxGitUnavailableNotice(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh on PATH: the POSIX shim cannot be built")
	}
	sb := newSandbox(t)
	sb.writePage(t, `<div>head <b>0000000</b></div>`)

	// A zero-byte `git` is exactly the shape .ps1:32-34 records: `Get-Command`
	// finds the NAME, but the call fails at launch time.
	//
	// It must be mode 0755: exec.LookPath (which os/exec uses to resolve the
	// program) SKIPS non-executable files on PATH and would quietly fall through
	// to the real git — measured, the first version of this test failed with a
	// block emitted by the real git. 0755 keeps it resolvable while still
	// failing at launch, which is the behaviour under test.
	shimDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(shimDir, "git"), nil, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	code, out, errOut := runReal(t, sb.dir)
	if code != 1 || out != "" || errOut != msgGitUnusable+"\n" {
		t.Errorf("exit=%d stdout=%q stderr=%q; want 1 + git-unusable notice", code, out, errOut)
	}
}

// TestRunSandboxCanaryNotice: git launches and exits 0 for EVERYTHING (a shim
// that always succeeds). The probe passes, the canary must not — otherwise the
// exit code means nothing and the guard would wave every stale page through.
func TestRunSandboxCanaryNotice(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh on PATH: the POSIX shim cannot be built")
	}
	sb := newSandbox(t)
	sb.writePage(t, `<div>head <b>0000000</b></div>`)

	shimDir := t.TempDir()
	shim := "#!/bin/sh\nexit 0\n"
	if err := os.WriteFile(filepath.Join(shimDir, "git"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	code, out, errOut := runReal(t, sb.dir)
	if code != 1 || out != "" || errOut != msgCanaryFailed+"\n" {
		t.Errorf("exit=%d stdout=%q stderr=%q; want 1 + canary notice", code, out, errOut)
	}
}

// --- helpers ---

// stubDeps returns Deps that walk the happy path (in sync), so each test can
// break exactly one collaborator and observe the branch it selects.
func stubDeps() Deps {
	return Deps{
		Resolve: func(string) workspace.Result {
			return workspace.Result{Workspace: "/ws", Repo: "/ws", Ok: true}
		},
		Probe:  func() bool { return true },
		Canary: func() bool { return true },
		Mainline: func(string) mainline.Result {
			return mainline.Result{Ref: "refs/heads/main", Name: "main", Ok: true}
		},
		ShortRef: func(string, string) (string, bool) { return "abcdef1", true },
		ResolveFull: func(repo, id string) (string, bool) {
			switch id {
			case "refs/heads/main", "deadbee":
				return fullA, true
			}
			return "", false
		},
		ReadPageName: func(string) page.NameResult {
			return page.NameResult{Name: page.DefaultPageName, Fault: false}
		},
		FindPage: func(string, string) (string, bool) { return "/ws/project-progress.html", true },
		ReadHead: func(string) (string, bool) { return "deadbee", true },
	}
}

// runOnce runs Run with buffers and returns (exit, stdout, stderr). A nil dep is
// a test bug, not a branch: fail loudly rather than nil-panic.
func runOnce(t *testing.T, args []string, d Deps) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := Run(args, &out, &errOut, d)
	return code, out.String(), errOut.String()
}

// runReal runs the production wiring against a sandbox workspace.
func runReal(t *testing.T, ws string) (int, string, string) {
	t.Helper()
	return runOnce(t, []string{"--workspace", ws}, DefaultDeps())
}

func wantSilent(t *testing.T, what string, code int, out, errOut string) {
	t.Helper()
	if code != 0 {
		t.Errorf("%s: exit=%d want 0", what, code)
	}
	if out != "" {
		t.Errorf("%s: stdout=%q want empty", what, out)
	}
	if errOut != "" {
		t.Errorf("%s: stderr=%q want empty", what, errOut)
	}
}

// sprintfReason is the reason builder, exposed for the byte-comparison test.
func sprintfReason(name, recorded, mainName, headShort string) string {
	return buildReason(name, recorded, mainName, headShort)
}

// sandbox is a temp workspace with a git repo, one commit on `main`, and a page.
type sandbox struct{ dir string }

func newSandbox(t *testing.T) *sandbox {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".claude", "hooks"), 0o755); err != nil {
		t.Fatal(err)
	}
	mustGit(t, dir, "init", "-q")
	mustGit(t, dir, "config", "user.email", "test@example.com")
	mustGit(t, dir, "config", "user.name", "Test")
	// Pin the branch name: mainline level 2 looks for refs/heads/main, and this
	// machine's init.defaultBranch is measured to be `master`.
	mustGit(t, dir, "symbolic-ref", "HEAD", "refs/heads/main")
	mustGit(t, dir, "commit", "-q", "--allow-empty", "-m", "seed")
	sb := &sandbox{dir: dir}
	sb.writePointer(t, "project-progress.html\n")
	return sb
}

func (s *sandbox) git(t *testing.T, args ...string) {
	t.Helper()
	mustGit(t, s.dir, args...)
}

func (s *sandbox) commitEmpty(t *testing.T, msg string) {
	t.Helper()
	s.git(t, "commit", "-q", "--allow-empty", "-m", msg)
}

func (s *sandbox) head(t *testing.T) string {
	t.Helper()
	return strings.TrimSpace(runGit(t, s.dir, "rev-parse", "HEAD"))
}

func (s *sandbox) writePage(t *testing.T, html string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(s.dir, "project-progress.html"), []byte(html), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (s *sandbox) writePointer(t *testing.T, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(s.dir, ".claude", "progress-page.txt"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func mustGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git %v in %s: %v: %s", args, dir, err, out)
	}
}

func runGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	out, err := c.Output()
	if err != nil {
		t.Fatalf("git %v in %s: %v", args, dir, err)
	}
	return string(out)
}

// Keep the shared libraries referenced here: if a future edit drops one from
// DefaultDeps, the compiler complains in production code, but naming them here
// documents which ones this package is allowed to depend on.
var (
	_ = git.Probe
	_ = sha.EqualFull
)
