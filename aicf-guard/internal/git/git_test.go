package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// White-box tests (package git) so we can assert on the unexported
// filterGitFamily / gitEnvFamily directly — the family-NOT-reducible invariant
// (ADR §1.3.3) is part of the contract. The integration tests exercise the real
// git binary; they require git on PATH (true on this machine). If git is ever
// missing, Probe/Canary fail loudly — correct, since the guard's premise is
// "git is usable".

// --- Positive probe & negative canary (ADR §1.3.2) ---

func TestProbe(t *testing.T) {
	// git --version must exit 0 on this machine (git is installed).
	if !Probe() {
		t.Fatal("Probe() = false; want true (git --version must exit 0)")
	}
}

func TestCanary(t *testing.T) {
	// The all-zero OID names no object in any repo → rev-parse --verify MUST
	// fail (exit != 0). This is the negative canary: it forces git to disagree
	// with the probe, making the exit code trustworthy rather than assumed.
	if !Canary() {
		t.Fatal("Canary() = false; want true (zero-OID rev-parse must fail non-zero)")
	}
}

// --- Checked: exit code is the criterion, text is payload (THE ONE RULE) ---

func TestCheckedSuccessExitZero(t *testing.T) {
	r := Checked("--version")
	if r.Exit != 0 {
		t.Fatalf("git --version: Exit=%d want 0; Text=%q", r.Exit, r.Text)
	}
	// Text is PAYLOAD: it should contain "git version" but we do NOT judge by it.
	if !strings.Contains(r.Text, "git version") {
		t.Errorf("Text=%q should contain 'git version' (payload check only, not criterion)", r.Text)
	}
}

func TestCheckedNonZeroExit(t *testing.T) {
	// rev-parse --verify of the zero OID MUST exit non-zero (same input as the
	// canary). The criterion is Exit != 0, NOT the emptiness of Text.
	r := Checked("rev-parse", "--verify", "--quiet", zeroOID+"^{commit}")
	if r.Exit == 0 {
		t.Fatalf("zero-OID rev-parse: Exit=0 want non-zero (canary input must fail)")
	}
}

func TestCheckedUnknownSubcommand(t *testing.T) {
	// `git not-a-real-subcommand` exits non-zero (128). The criterion is Exit.
	r := Checked("not-a-real-subcommand")
	if r.Exit == 0 {
		t.Fatalf("git not-a-real-subcommand: Exit=0 want non-zero")
	}
}

// --- filterGitFamily: all 9 vars filtered (ADR §1.3.3, family NOT reducible) ---

func TestFilterGitFamilyAllNine(t *testing.T) {
	// Build an environ with all 9 family members + ordinary vars.
	in := []string{
		"PATH=/usr/bin",
		"HOME=/home/user",
		"USER=me",
		"GIT_DIR=/evil/a",
		"GIT_WORK_TREE=/evil/b",
		"GIT_OBJECT_DIRECTORY=/evil/c",
		"GIT_COMMON_DIR=/evil/d",
		"GIT_INDEX_FILE=/evil/e",
		"GIT_ALTERNATE_OBJECT_DIRECTORIES=/evil/f",
		"GIT_CEILING_DIRECTORIES=/evil/g",
		"GIT_NAMESPACE=evil",
		"GIT_PREFIX=/evil/",
	}
	out := filterGitFamily(in)
	// No GIT_* family member may survive.
	for _, kv := range out {
		name, _, _ := strings.Cut(kv, "=")
		for _, g := range gitEnvFamily {
			if name == g {
				t.Errorf("family member %q NOT filtered: %s", g, kv)
			}
		}
	}
	// The 3 ordinary vars must survive.
	ordinary := map[string]bool{
		"PATH=/usr/bin":   false,
		"HOME=/home/user": false,
		"USER=me":         false,
	}
	for _, kv := range out {
		if _, ok := ordinary[kv]; ok {
			ordinary[kv] = true
		}
	}
	for kv, seen := range ordinary {
		if !seen {
			t.Errorf("ordinary var %q dropped by filter (must survive)", kv)
		}
	}
	if len(out) != 3 {
		t.Errorf("filtered len=%d want 3 (only ordinary vars survive); got %v", len(out), out)
	}
}

func TestFilterGitFamilyEmpty(t *testing.T) {
	out := filterGitFamily(nil)
	if len(out) != 0 {
		t.Errorf("filter(nil) = %v want empty", out)
	}
}

func TestFilterGitFamilyMalformedDropped(t *testing.T) {
	// An entry with no '=' is malformed and dropped (can't be a valid env var).
	out := filterGitFamily([]string{"MALFORMED", "PATH=/usr/bin"})
	if len(out) != 1 || out[0] != "PATH=/usr/bin" {
		t.Errorf("filter(malformed) = %v want [PATH=/usr/bin]", out)
	}
}

// --- The critical GAP-013① / GAP-031 hijack test ---

// TestCheckedFiltersGitEnvFamily is the integration test for the GAP-013① fix:
// an ambient GIT_DIR (and GIT_OBJECT_DIRECTORY) HIJACKS `git -C <repo>` — `-C`
// picks the working directory, but GIT_DIR overrides repository discovery
// entirely, so the guard would read ANOTHER repo's HEAD. With GIT_DIR pointing
// at a repo whose HEAD happened to match the page, the .ps1 exited 0 SILENTLY
// and waved a stale page through (measured). Checked MUST filter the family so
// the child git sees only `-C <repo>` and discovers the right repo.
//
// This also covers GAP-031: clearing only GIT_DIR is insufficient —
// GIT_OBJECT_DIRECTORY / GIT_COMMON_DIR hijack `rev-parse --verify <ref>^{commit}`
// (measured as a regression of cell A11). We set BOTH plus GIT_WORK_TREE and
// confirm no hijack on BOTH a plain `rev-parse HEAD` AND a `rev-parse --verify
// <ref>^{commit}` (the exact shape GAP-031 found hijackable).
func TestCheckedFiltersGitEnvFamily(t *testing.T) {
	a := initRepoWithCommit(t, "repo-a")
	b := initRepoWithCommit(t, "repo-b")
	aHead := revParseHead(t, a)
	bHead := revParseHead(t, b)
	if aHead == bHead {
		t.Fatalf("setup: repos have identical HEAD (%s); need distinct commits to detect hijack", aHead)
	}

	// Hijack: point GIT_DIR and GIT_OBJECT_DIRECTORY at repo A. WITHOUT
	// filtering, `git -C b rev-parse HEAD` would read A's HEAD (the hijack).
	// t.Setenv saves/restores the parent env automatically after the test.
	t.Setenv("GIT_DIR", filepath.Join(a, ".git"))
	t.Setenv("GIT_OBJECT_DIRECTORY", filepath.Join(a, ".git", "objects"))
	// Set more of the family too — proves the WHOLE family is filtered, not
	// just GIT_DIR (GAP-031: clearing only GIT_DIR is insufficient).
	t.Setenv("GIT_COMMON_DIR", filepath.Join(a, ".git"))
	t.Setenv("GIT_WORK_TREE", a)

	// Checked must filter the family so the child sees only `-C b`.
	r := Checked("-C", b, "rev-parse", "HEAD")
	if r.Exit != 0 {
		t.Fatalf("Checked(-C b rev-parse HEAD): Exit=%d want 0; Text=%q", r.Exit, r.Text)
	}
	if r.Text != bHead {
		t.Errorf("GIT_* hijack NOT filtered: got HEAD %q, want %q (repo b); the family clearing is broken",
			r.Text, bHead)
	}

	// Also exercise `rev-parse --verify <ref>^{commit}` — the exact shape that
	// GAP-031 found was hijackable by GIT_OBJECT_DIRECTORY / GIT_COMMON_DIR.
	r2 := Checked("-C", b, "rev-parse", "--verify", "--quiet", "HEAD^{commit}")
	if r2.Exit != 0 {
		t.Fatalf("Checked(-C b rev-parse --verify HEAD^{{commit}}): Exit=%d want 0; Text=%q", r2.Exit, r2.Text)
	}
	if r2.Text != bHead {
		t.Errorf("GIT_OBJECT_DIRECTORY/GIT_COMMON_DIR hijack NOT filtered on --verify: got %q want %q",
			r2.Text, bHead)
	}
}

// TestCheckedNoEnvMutation verifies Checked does NOT mutate the parent process
// environment — the GIT_* family filtering happens in the CHILD only (via
// cmd.Env). This is what makes Checked goroutine-safe (vs the .ps1 save/restore
// in a single-threaded host). If Checked ever called os.Setenv/Unsetenv, this
// test would catch it.
func TestCheckedNoEnvMutation(t *testing.T) {
	t.Setenv("GIT_DIR", "/evil/should/not/persist")
	_ = Checked("--version")
	// After the call, the parent env must STILL have the value t.Setenv set
	// (Checked must not have cleared or changed it).
	got, ok := os.LookupEnv("GIT_DIR")
	if !ok {
		t.Fatal("GIT_DIR was unset by Checked (parent env mutated); filtering must be child-only")
	}
	if got != "/evil/should/not/persist" {
		t.Errorf("GIT_DIR changed by Checked: got %q want /evil/should/not/persist (parent env mutated)", got)
	}
}

// TestCheckedGoroutineSafe runs concurrent Checked calls under -race. Since
// Checked builds a filtered child env from os.Environ() (read-only) and never
// mutates process state, concurrent calls must not race. The -race detector
// will flag any data race.
func TestCheckedGoroutineSafe(t *testing.T) {
	const n = 16
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := Checked("--version")
			if r.Exit != 0 {
				errs <- &gcErr{"--version", r.Exit}
				return
			}
			// A second call with different args — exercises the same code path.
			r2 := Checked("rev-parse", "--verify", "--quiet", zeroOID+"^{commit}")
			if r2.Exit == 0 {
				errs <- &gcErr{"canary (must fail)", r2.Exit}
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Errorf("concurrent Checked failure: %v", e)
	}
}

type gcErr struct {
	msg  string
	code int
}

func (e *gcErr) Error() string { return e.msg + " exit=" + strconv.Itoa(e.code) }

// --- helpers for fixture repos (use exec.Command directly, NOT Checked, so
// they are not affected by — and do not test — the family filtering) ---

// initRepoWithCommit creates a fresh git repo in a temp dir with one empty
// commit on a branch named after `label` (so distinct labels → distinct HEADs).
func initRepoWithCommit(t *testing.T, label string) string {
	t.Helper()
	dir := t.TempDir()
	mustGit(t, dir, "init", "-q")
	mustGit(t, dir, "config", "user.email", "test@example.com")
	mustGit(t, dir, "config", "user.name", "Test")
	// Put the commit on a branch named after the label → distinct repos get
	// distinct refs (and almost certainly distinct commit SHAs, since the
	// commit message differs).
	mustGit(t, dir, "symbolic-ref", "HEAD", "refs/heads/"+label)
	mustGit(t, dir, "commit", "-q", "--allow-empty", "-m", label)
	return dir
}

// revParseHead returns the full HEAD SHA of `dir` (via exec.Command directly).
func revParseHead(t *testing.T, dir string) string {
	t.Helper()
	c := exec.Command("git", "-C", dir, "rev-parse", "HEAD")
	out, err := c.Output()
	if err != nil {
		t.Fatalf("rev-parse HEAD in %s: %v", dir, err)
	}
	return strings.TrimSpace(string(out))
}

// mustGit runs git in dir and fails the test on any error.
func mustGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git %v in %s: %v: %s", args, dir, err, out)
	}
}
