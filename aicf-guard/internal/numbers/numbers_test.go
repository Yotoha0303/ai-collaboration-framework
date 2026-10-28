package numbers

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCollapseRefsLocalShadowsRemote(t *testing.T) {
	refs := []string{
		"refs/remotes/origin/feature",
		"refs/heads/feature",
		"refs/heads/main",
		"refs/remotes/origin/main",
		"refs/remotes/origin/HEAD",
	}
	got := collapseRefs(refs)
	want := []string{"refs/heads/feature", "refs/heads/main"}
	if len(got) != len(want) {
		t.Fatalf("collapseRefs = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("collapseRefs[%d] = %q, want %q (full: %v)", i, got[i], want[i], got)
		}
	}
}

func TestCollapseRefsCaseSensitive(t *testing.T) {
	// Branch names differing only in case are two branches on a
	// case-sensitive filesystem, so both must survive the fold.
	got := collapseRefs([]string{"refs/heads/Feature", "refs/heads/feature"})
	if len(got) != 2 {
		t.Fatalf("collapseRefs = %v, want both case variants kept", got)
	}
}

func TestCollapseRefsNestedBranchNames(t *testing.T) {
	got := collapseRefs([]string{"refs/remotes/origin/feature/foo", "refs/heads/feature/foo"})
	if len(got) != 1 || got[0] != "refs/heads/feature/foo" {
		t.Fatalf("collapseRefs = %v, want [refs/heads/feature/foo]", got)
	}
}

func TestParseLsTreeRecord(t *testing.T) {
	num, id, ok := parseLsTreeRecord("100644 blob abcdef1234567890\tdocs/changes/001-fix.md")
	if !ok || num != "001" || id != "docs/changes/001-fix.md@abcdef1234567890" {
		t.Fatalf("parse = (%q, %q, %v), want (001, docs/changes/001-fix.md@abcdef1234567890, true)", num, id, ok)
	}
	if _, _, ok := parseLsTreeRecord("100644 blob abcdef1234567890\tdocs/changes/12-fix.md"); ok {
		t.Fatalf("2-digit prefix must not parse as a number")
	}
	if _, _, ok := parseLsTreeRecord("not a record"); ok {
		t.Fatalf("malformed record must not parse")
	}
}

func TestFormatCollisions(t *testing.T) {
	byNum := map[string]map[string]struct{}{
		"001": {"docs/changes/001-a.md@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {}, "docs/changes/001-b.md@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": {}},
		"002": {"docs/changes/002-a.md@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {}},
	}
	got := formatCollisions("proj", byNum)
	if len(got) != 1 {
		t.Fatalf("formatCollisions = %v, want exactly the 001 collision", got)
	}
	if !strings.Contains(got[0], "[proj] 001") || !strings.Contains(got[0], "001-a.md (aaaaaaa)") || !strings.Contains(got[0], "001-b.md (bbbbbbb)") {
		t.Fatalf("formatCollisions = %q, want proj/001 with both files and 7-char oids", got[0])
	}
}

// --- sandbox tests against a real git repo ---

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com", "GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func newSandboxRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH")
	}
	ws := t.TempDir()
	if err := os.MkdirAll(filepath.Join(ws, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	runGit(t, ws, "init", "-b", "main")
	runGit(t, ws, "config", "commit.gpgsign", "false")
	if err := os.MkdirAll(filepath.Join(ws, "docs", "changes"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(ws, "docs", "changes", "001-a.md"), []byte("a\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, ws, "add", ".")
	runGit(t, ws, "commit", "-m", "001-a")
	return ws
}

func TestRunSandboxCollision(t *testing.T) {
	ws := newSandboxRepo(t)
	runGit(t, ws, "checkout", "-b", "feature")
	if err := os.WriteFile(filepath.Join(ws, "docs", "changes", "001-b.md"), []byte("b\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, ws, "add", ".")
	runGit(t, ws, "commit", "-m", "001-b")
	runGit(t, ws, "checkout", "main")

	var stderr bytes.Buffer
	code := Run([]string{"--workspace", ws}, &bytes.Buffer{}, &stderr)
	if code != 1 {
		t.Fatalf("Run = %d, want 1 (collision)", code)
	}
	if !strings.Contains(stderr.String(), "001") || !strings.Contains(stderr.String(), "001-a.md") || !strings.Contains(stderr.String(), "001-b.md") {
		t.Fatalf("stderr = %q, want the 001 collision naming both files", stderr.String())
	}
}

func TestRunSandboxSameFileIsNotCollision(t *testing.T) {
	ws := newSandboxRepo(t)
	runGit(t, ws, "checkout", "-b", "feature")
	// No new file: both branches name the SAME (path, oid) for 001.
	runGit(t, ws, "checkout", "main")
	var stderr bytes.Buffer
	code := Run([]string{"--workspace", ws}, &bytes.Buffer{}, &stderr)
	if code != 0 || stderr.String() != "" {
		t.Fatalf("Run = %d stderr = %q, want 0 and silence (same file, not a collision)", code, stderr.String())
	}
}

func TestRunSandboxNoRepoIsSilent(t *testing.T) {
	ws := t.TempDir()
	if err := os.MkdirAll(filepath.Join(ws, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	code := Run([]string{"--workspace", ws}, &bytes.Buffer{}, &stderr)
	if code != 0 || stderr.String() != "" {
		t.Fatalf("Run = %d stderr = %q, want 0 and silence (not initialised)", code, stderr.String())
	}
}
