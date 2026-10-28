package workspace

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// White-box tests (package workspace) to access resolveWorkspaceLayers,
// isWorkspace, resolveRepo directly. Fixture repos use exec.Command directly
// (NOT git.Checked) so setup is independent of the family filtering.

// --- resolveWorkspaceLayers: the 4-layer priority ---

func TestLayerFlagWins(t *testing.T) {
	// An explicit flag that IS a workspace wins, even when CPD/exe/cwd point
	// elsewhere (precedence: flag > CPD > exe > cwd).
	flag := makeWorkspace(t)
	cpd := makeWorkspace(t)
	exeWS := makeWorkspace(t)
	cwdWS := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers(flag, cpd, exeDirOf(exeWS), cwdWS)
	if !ok || got != flag {
		t.Errorf("flag layer: got (%q,%v), want (%q,true)", got, ok, flag)
	}
}

func TestLayerFlagInvalidFails(t *testing.T) {
	// A non-empty flag that is NOT a workspace FAILS — no fall-through to lower
	// layers. An explicit override is authoritative, not advisory.
	tmp := t.TempDir() // no .claude/ or .agents/
	cpd := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers(tmp, cpd, "", "")
	if ok {
		t.Errorf("flag=%q is not a workspace; expected failure, got (%q,true)", tmp, got)
	}
}

func TestLayerFlagEmptyStringSkipped(t *testing.T) {
	// An empty flag string is "not provided", not "provided but empty" — layer
	// 1 is skipped and layer 2 (CPD) takes over.
	cpd := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers("", cpd, "", "")
	if !ok || got != cpd {
		t.Errorf("empty flag should skip to CPD: got (%q,%v), want (%q,true)", got, ok, cpd)
	}
}

func TestLayerCPD(t *testing.T) {
	cpd := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers("", cpd, "", "")
	if !ok || got != cpd {
		t.Errorf("CPD layer: got (%q,%v), want (%q,true)", got, ok, cpd)
	}
}

func TestLayerCPDInvalidSkipped(t *testing.T) {
	// A CPD that is not a workspace is skipped; fall through to exe/cwd.
	tmp := t.TempDir()
	cwd := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers("", tmp, "", cwd)
	if !ok || got != cwd {
		t.Errorf("invalid CPD should fall through to cwd: got (%q,%v), want (%q,true)", got, ok, cwd)
	}
}

func TestLayerExeWalkUp(t *testing.T) {
	// Binary in <ws>/.claude/hooks/ → walk up to <ws>.
	ws := makeWorkspace(t)
	exeDir := filepath.Join(ws, ".claude", "hooks")
	if err := os.MkdirAll(exeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := resolveWorkspaceLayers("", "", exeDir, "")
	if !ok || got != ws {
		t.Errorf("exe walk-up: got (%q,%v), want (%q,true)", got, ok, ws)
	}
}

func TestLayerExeWalkUpAgentsDir(t *testing.T) {
	// Binary in <ws>/.agents/hooks/ → walk up to <ws> (.agents/ also marks a ws).
	ws := makeWorkspace(t)
	// Remove .claude to prove .agents alone is sufficient.
	if err := os.RemoveAll(filepath.Join(ws, ".claude")); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(ws, ".agents", "hooks"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := resolveWorkspaceLayers("", "", filepath.Join(ws, ".agents", "hooks"), "")
	if !ok || got != ws {
		t.Errorf("exe walk-up via .agents: got (%q,%v), want (%q,true)", got, ok, ws)
	}
}

func TestLayerCWDWalkUp(t *testing.T) {
	ws := makeWorkspace(t)
	cwd := filepath.Join(ws, "sub", "deep", "dir")
	if err := os.MkdirAll(cwd, 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := resolveWorkspaceLayers("", "", "", cwd)
	if !ok || got != ws {
		t.Errorf("cwd walk-up: got (%q,%v), want (%q,true)", got, ok, ws)
	}
}

func TestLayerNoneResolve(t *testing.T) {
	// No flag, no CPD, exe in /tmp (no .claude/.agents above), cwd in /tmp.
	tmp := t.TempDir()
	got, ok := resolveWorkspaceLayers("", "", tmp, tmp)
	if ok {
		t.Errorf("expected failure when no layer resolves; got (%q,true)", got)
	}
}

func TestLayerPrecedenceFlagOverCPD(t *testing.T) {
	ws1 := makeWorkspace(t)
	ws2 := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers(ws1, ws2, "", "")
	if !ok || got != ws1 {
		t.Errorf("flag must beat CPD: got (%q,%v), want (%q,true)", got, ok, ws1)
	}
}

func TestLayerPrecedenceCPDOverExe(t *testing.T) {
	cpd := makeWorkspace(t)
	exeWS := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers("", cpd, exeDirOf(exeWS), "")
	if !ok || got != cpd {
		t.Errorf("CPD must beat exe: got (%q,%v), want (%q,true)", got, ok, cpd)
	}
}

func TestLayerPrecedenceExeOverCWD(t *testing.T) {
	exeWS := makeWorkspace(t)
	cwdWS := makeWorkspace(t)
	got, ok := resolveWorkspaceLayers("", "", exeDirOf(exeWS), cwdWS)
	if !ok || got != exeWS {
		t.Errorf("exe must beat cwd: got (%q,%v), want (%q,true)", got, ok, exeWS)
	}
}

// --- isWorkspace ---

func TestIsWorkspaceClaude(t *testing.T) {
	ws := makeWorkspace(t)
	if !isWorkspace(ws) {
		t.Errorf("isWorkspace(%q) = false; want true (has .claude/)", ws)
	}
}

func TestIsWorkspaceAgents(t *testing.T) {
	ws := t.TempDir()
	if err := os.MkdirAll(filepath.Join(ws, ".agents"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !isWorkspace(ws) {
		t.Errorf("isWorkspace(%q) = false; want true (has .agents/)", ws)
	}
}

func TestIsWorkspaceNeither(t *testing.T) {
	tmp := t.TempDir()
	if isWorkspace(tmp) {
		t.Errorf("isWorkspace(%q) = true; want false (no .claude/.agents)", tmp)
	}
}

func TestIsWorkspaceEmpty(t *testing.T) {
	if isWorkspace("") {
		t.Error(`isWorkspace("") = true; want false`)
	}
}

// --- resolveRepo: @[ws, ws/project], ws first, GAP-009 ---

func TestResolveRepoSelfHosted(t *testing.T) {
	// ws itself is a repo (self-hosted layout, the framework's own case).
	ws := makeWorkspace(t)
	initBareRepo(t, ws)
	got := resolveRepo(ws)
	if got != ws {
		t.Errorf("resolveRepo: got %q want %q (ws is repo)", got, ws)
	}
}

func TestResolveRepoProjectChild(t *testing.T) {
	// ws has no .git; ws/project does (target layout).
	ws := makeWorkspace(t)
	proj := filepath.Join(ws, "project")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	initBareRepo(t, proj)
	got := resolveRepo(ws)
	if got != proj {
		t.Errorf("resolveRepo: got %q want %q (project child is repo)", got, proj)
	}
}

func TestResolveRepoWSPrecedence(t *testing.T) {
	// BOTH ws and ws/project have .git → ws wins (order matters, ADR §2.2).
	ws := makeWorkspace(t)
	initBareRepo(t, ws)
	proj := filepath.Join(ws, "project")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	initBareRepo(t, proj)
	got := resolveRepo(ws)
	if got != ws {
		t.Errorf("resolveRepo: got %q want %q (ws must be tried first)", got, ws)
	}
}

func TestResolveRepoNone(t *testing.T) {
	// ws has no .git, no project/ child with .git → "".
	ws := makeWorkspace(t)
	got := resolveRepo(ws)
	if got != "" {
		t.Errorf("resolveRepo: got %q want empty (no repo)", got)
	}
}

func TestResolveRepoDotGitFileNotResolving(t *testing.T) {
	// GAP-009: a `.git` FILE (not dir) that doesn't resolve as a repo must NOT
	// be accepted. We write a bogus `.git` file (not a valid gitdir pointer)
	// and confirm resolveRepo skips it. (A bare `git init` makes `.git` a dir;
	// here we test the "entry exists but rev-parse fails" path.)
	ws := makeWorkspace(t)
	bogus := filepath.Join(ws, ".git")
	if err := os.WriteFile(bogus, []byte("not a gitdir pointer"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := resolveRepo(ws)
	if got != "" {
		t.Errorf("GAP-009: bogus .git file resolved to %q; want empty (must pass rev-parse --git-dir)", got)
	}
}

// --- Resolve: end-to-end ---

func TestResolveEndToEndFlagWithRepo(t *testing.T) {
	ws := makeWorkspace(t)
	initBareRepo(t, ws)
	r := Resolve(ws)
	if !r.Ok {
		t.Fatalf("Resolve: Ok=false want true; Repo=%q", r.Repo)
	}
	if r.Workspace != ws || r.Repo != ws {
		t.Errorf("Resolve: Workspace=%q Repo=%q; want both %q", r.Workspace, r.Repo, ws)
	}
}

func TestResolveEndToEndFlagNoRepo(t *testing.T) {
	// Workspace found (has .claude/) but no repo → Ok=false, Workspace set.
	ws := makeWorkspace(t)
	r := Resolve(ws)
	if r.Ok {
		t.Error("Resolve: Ok=true want false (no repo)")
	}
	if r.Workspace != ws {
		t.Errorf("Resolve: Workspace=%q want %q (workspace found, repo not)", r.Workspace, ws)
	}
}

func TestResolveEndToEndFlagInvalid(t *testing.T) {
	tmp := t.TempDir()
	r := Resolve(tmp)
	if r.Ok {
		t.Error("Resolve: Ok=true want false (not a workspace)")
	}
	if r.Workspace != "" {
		t.Errorf("Resolve: Workspace=%q want empty (invalid flag → no workspace)", r.Workspace)
	}
}

// --- ResolveFrom: the injectable form (progress + tests take this route) ---

func TestResolveFromExecutableIsAPath(t *testing.T) {
	// The .ps1 self-locates from Split-Path -Parent $PSCommandPath
	// (check-progress.ps1:185) — the parent of the SCRIPT. The binary's
	// equivalent is the directory of the EXECUTABLE, so ResolveFrom must take a
	// path-to-binary and walk up from its dir. Passing the dir itself would
	// resolve the same ws one level too high in the real layout
	// (<ws>/.claude/hooks/ vs <ws>/.claude/), so this pins which one it is.
	ws := makeWorkspace(t)
	exe := exeDirOf(ws) + "/aicf-guard"
	got, ok := resolveWorkspaceLayers("", "", filepath.Dir(exe), "")
	if !ok || got != ws {
		t.Fatalf("setup: exe dir walk-up failed: (%q,%v)", got, ok)
	}
	r := ResolveFrom("", "", exe, "")
	if r.Workspace != ws {
		t.Errorf("ResolveFrom(executable=%q).Workspace=%q want %q", exe, r.Workspace, ws)
	}
}

func TestResolveFromRepo(t *testing.T) {
	ws := makeWorkspace(t)
	initBareRepo(t, ws)
	r := ResolveFrom(ws, "", "", "")
	if !r.Ok {
		t.Fatalf("ResolveFrom: Ok=false want true")
	}
	if r.Workspace != ws || r.Repo != ws {
		t.Errorf("ResolveFrom: Workspace=%q Repo=%q; want both %q", r.Workspace, r.Repo, ws)
	}
}

func TestResolveFromAllEmpty(t *testing.T) {
	r := ResolveFrom("", "", "", "")
	if r.Ok || r.Workspace != "" || r.Repo != "" {
		t.Errorf("ResolveFrom(all empty) = %+v; want zero", r)
	}
}

// TestResolveUsesProjectDir: the real Resolve must read CLAUDE_PROJECT_DIR
// (layer 2). This is the only test that touches the OS plumbing; layer 1 is
// empty and layer 2 wins before exe/cwd are ever consulted.
func TestResolveUsesProjectDir(t *testing.T) {
	ws := makeWorkspace(t)
	initBareRepo(t, ws)
	t.Setenv("CLAUDE_PROJECT_DIR", ws)
	r := Resolve("")
	if r.Workspace != ws {
		t.Errorf("Resolve().Workspace=%q want %q (from CLAUDE_PROJECT_DIR)", r.Workspace, ws)
	}
}

// --- FindPage: two candidates, ws first (.ps1:212-215) ---

func TestFindPageAtWorkspace(t *testing.T) {
	ws := makeWorkspace(t)
	page := filepath.Join(ws, "project-progress.html")
	if err := os.WriteFile(page, []byte("<html></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, ok := FindPage(ws, "project-progress.html")
	if !ok || got != page {
		t.Errorf("FindPage = (%q,%v); want (%q,true)", got, ok, page)
	}
}

func TestFindPageAtParentOfWorkspace(t *testing.T) {
	// Pre-move layout: `.claude/` lives INSIDE the repo, so the page is the
	// sibling of the repo, not of `.claude/`. Second candidate must hit.
	parent := t.TempDir()
	ws := filepath.Join(parent, "repo")
	if err := os.MkdirAll(filepath.Join(ws, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	page := filepath.Join(parent, "project-progress.html")
	if err := os.WriteFile(page, []byte("<html></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, ok := FindPage(ws, "project-progress.html")
	if !ok || got != page {
		t.Errorf("FindPage = (%q,%v); want (%q,true)", got, ok, page)
	}
}

func TestFindPageWorkspaceWinsOverParent(t *testing.T) {
	// Both candidates exist ⇒ ws first (order matters; same reasoning as the
	// repo candidates: the current layout must win).
	parent := t.TempDir()
	ws := filepath.Join(parent, "repo")
	if err := os.MkdirAll(filepath.Join(ws, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(ws, "project-progress.html")
	for _, p := range []string{want, filepath.Join(parent, "project-progress.html")} {
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, ok := FindPage(ws, "project-progress.html")
	if !ok || got != want {
		t.Errorf("FindPage = (%q,%v); want (%q,true) (ws candidate wins)", got, ok, want)
	}
}

func TestFindPageNone(t *testing.T) {
	ws := makeWorkspace(t)
	if got, ok := FindPage(ws, "project-progress.html"); ok {
		t.Errorf("FindPage = (%q,true); want (\"\",false) when neither candidate exists", got)
	}
}

func TestFindPageDirectoryCountsAsExisting(t *testing.T) {
	// Deliberate: the .ps1 uses Test-Path, which is true for a DIRECTORY. The
	// directory is then "the page" and reading it fails — which lands on the
	// same silent branch as a missing page. Pinning the loose test keeps the
	// branch structure identical to the .ps1 instead of inventing a new one.
	ws := makeWorkspace(t)
	if err := os.MkdirAll(filepath.Join(ws, "project-progress.html"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := FindPage(ws, "project-progress.html")
	if !ok || got != filepath.Join(ws, "project-progress.html") {
		t.Errorf("FindPage(dir) = (%q,%v); want the dir path,true (Test-Path semantics)", got, ok)
	}
}

func TestFindPageEmptyInputs(t *testing.T) {
	ws := makeWorkspace(t)
	if _, ok := FindPage("", "x.html"); ok {
		t.Error("FindPage(\"\", …) ok=true; want false")
	}
	if _, ok := FindPage(ws, ""); ok {
		t.Error("FindPage(…, \"\") ok=true; want false")
	}
}

// --- helpers ---

// makeWorkspace creates a temp dir with a `.claude/` subdir (the workspace
// marker). Returns the dir path.
func makeWorkspace(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir
}

// exeDirOf returns a hooks dir under ws (simulating the binary location).
func exeDirOf(ws string) string {
	return filepath.Join(ws, ".claude", "hooks")
}

// initBareRepo runs `git init -q` in dir (no commit). Enough for
// `git rev-parse --git-dir` to exit 0.
func initBareRepo(t *testing.T, dir string) {
	t.Helper()
	c := exec.Command("git", "init", "-q", dir)
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git init %s: %v: %s", dir, err, out)
	}
}
