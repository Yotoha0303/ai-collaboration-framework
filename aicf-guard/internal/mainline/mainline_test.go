package mainline_test

import (
	"os/exec"
	"strings"
	"testing"

	"aicf-guard/internal/mainline"
)

// Integration tests exercising the real git binary. Each level of the
// three-level fallback is set up as a distinct fixture so the level that hits
// is unambiguous.

// TestResolveOriginHead: level 1 hits when refs/remotes/origin/HEAD is set and
// points to a resolvable commit.
func TestResolveOriginHead(t *testing.T) {
	repo := initRepoOnMain(t)
	addOriginHead(t, repo, "main")
	r := mainline.Resolve(repo)
	if !r.Ok {
		t.Fatalf("Ok=false want true; repo=%s", repo)
	}
	wantRef := "refs/remotes/origin/main"
	if r.Ref != wantRef {
		t.Errorf("Ref=%q want %q (level 1)", r.Ref, wantRef)
	}
	if r.Name != "origin/main" {
		t.Errorf("Name=%q want %q", r.Name, "origin/main")
	}
}

// TestResolveMain: level 2 hits when there is no origin/HEAD but refs/heads/main
// resolves. This is the common case for a local-only repo.
func TestResolveMain(t *testing.T) {
	repo := initRepoOnMain(t) // no origin/HEAD set
	r := mainline.Resolve(repo)
	if !r.Ok {
		t.Fatalf("Ok=false want true")
	}
	if r.Ref != "refs/heads/main" {
		t.Errorf("Ref=%q want refs/heads/main (level 2)", r.Ref)
	}
	if r.Name != "main" {
		t.Errorf("Name=%q want main", r.Name)
	}
}

// TestResolveHEADFallback: level 3 hits when there is no origin/HEAD and no
// refs/heads/main (HEAD points to a differently-named branch). The Name MUST
// say "未找到主干" so a reader of the reason string can tell this is the fallback.
func TestResolveHEADFallback(t *testing.T) {
	repo := initRepoOnBranch(t, "develop") // no main branch
	r := mainline.Resolve(repo)
	if !r.Ok {
		t.Fatalf("Ok=false want true (HEAD must resolve)")
	}
	if r.Ref != "HEAD" {
		t.Errorf("Ref=%q want HEAD (level 3 fallback)", r.Ref)
	}
	if r.Name != "HEAD（未找到主干）" {
		t.Errorf("Name=%q want %q (fallback must be named)", r.Name, "HEAD（未找到主干）")
	}
}

// TestResolveUnborn: all three levels fail (no commit at all) → Ok=false.
// This is the "unborn repo" case (GAP-012 in the .ps1): the page-existence
// premise doesn't apply, so the caller stays silent.
func TestResolveUnborn(t *testing.T) {
	dir := t.TempDir()
	mustGit(t, dir, "init", "-q") // no commit → HEAD unborn
	r := mainline.Resolve(dir)
	if r.Ok {
		t.Errorf("Ok=true want false (unborn repo: all 3 levels must fail); Ref=%q Name=%q", r.Ref, r.Name)
	}
}

// TestResolveOriginHeadNonCommitFallsToMain: level 1 requires the target to peel
// to a COMMIT (`<ref>^{commit}`), not merely to exist. A symref pointing at a
// blob/tree ref resolves as an object but must not be accepted as the mainline —
// a page recording a commit id would then be compared against a non-commit and
// reported as lagging forever. This pins the `^{commit}` peel on level 1, which
// the dangling-ref test above does not reach (that one fails at the ref lookup
// itself, never at the peel).
func TestResolveOriginHeadNonCommitFallsToMain(t *testing.T) {
	repo := initRepoOnMain(t)
	blob := strings.TrimSpace(runGitStdin(t, repo, "hi\n", "hash-object", "-w", "--stdin"))
	mustGit(t, repo, "update-ref", "refs/remotes/origin/weird", blob)
	mustGit(t, repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/weird")
	r := mainline.Resolve(repo)
	if !r.Ok {
		t.Fatalf("Ok=false want true (should fall to main)")
	}
	if r.Ref != "refs/heads/main" {
		t.Errorf("Ref=%q want refs/heads/main (level 1 target is a blob, must be rejected)", r.Ref)
	}
	if r.Name != "main" {
		t.Errorf("Name=%q want main", r.Name)
	}
}

// TestResolveEmptyRepo: an empty repo string → Ok=false (defensive).
func TestResolveEmptyRepo(t *testing.T) {
	r := mainline.Resolve("")
	if r.Ok {
		t.Error("Resolve(\"\"): Ok=true want false")
	}
}

// TestResolveOriginHeadUnbornDoesNotHitLevel1: if origin/HEAD points at an
// unborn/dangling ref, symbolic-ref may succeed but rev-parse --verify fails,
// so level 1 is skipped and level 2 (main) takes over. This is the GAP-031
// subtlety: "symbolic-ref alone is NOT enough".
func TestResolveOriginHeadUnbornFallsToMain(t *testing.T) {
	repo := initRepoOnMain(t)
	// Point origin/HEAD at a remote branch that does NOT exist (dangling).
	mustGit(t, repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/nonexistent")
	r := mainline.Resolve(repo)
	// Level 1 must fail (rev-parse --verify of nonexistent ref fails); level 2 hits.
	if !r.Ok {
		t.Fatalf("Ok=false want true (should fall to main)")
	}
	if r.Ref != "refs/heads/main" {
		t.Errorf("Ref=%q want refs/heads/main (level 1 must fail on dangling, fall to level 2)", r.Ref)
	}
}

// --- helpers (exec.Command directly, NOT git.Checked) ---

// initRepoOnMain creates a repo with one commit on `main`.
func initRepoOnMain(t *testing.T) string {
	t.Helper()
	return initRepoOnBranch(t, "main")
}

// initRepoOnBranch creates a repo with one commit on the named branch (so
// `main` either exists or not depending on the branch name).
func initRepoOnBranch(t *testing.T, branch string) string {
	t.Helper()
	dir := t.TempDir()
	mustGit(t, dir, "init", "-q")
	mustGit(t, dir, "config", "user.email", "test@example.com")
	mustGit(t, dir, "config", "user.name", "Test")
	// Force the initial branch name (independent of init.defaultBranch).
	mustGit(t, dir, "symbolic-ref", "HEAD", "refs/heads/"+branch)
	mustGit(t, dir, "commit", "-q", "--allow-empty", "-m", "init on "+branch)
	return dir
}

// addOriginHead creates refs/remotes/origin/<branch> pointing to HEAD and sets
// the origin/HEAD symref → level 1 hits.
func addOriginHead(t *testing.T, repo, branch string) {
	t.Helper()
	mustGit(t, repo, "update-ref", "refs/remotes/origin/"+branch, "HEAD")
	mustGit(t, repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/"+branch)
}

func mustGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git %v in %s: %v: %s", args, dir, err, out)
	}
}

// runGitStdin runs git with stdin so a blob can be written without a worktree
// file (a pure object-store fixture).
func runGitStdin(t *testing.T, dir, stdin string, args ...string) string {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	c.Stdin = strings.NewReader(stdin)
	out, err := c.Output()
	if err != nil {
		t.Fatalf("git %v (stdin) in %s: %v", args, dir, err)
	}
	return string(out)
}
