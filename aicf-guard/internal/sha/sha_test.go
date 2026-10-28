package sha_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"aicf-guard/internal/sha"
)

// Integration tests exercising the real git binary. Each test builds a fixture
// repo and exercises the package against real object ids.
//
// Fixture setup deliberately uses exec.Command directly rather than
// git.Checked: setup must be independent of the code under test (if Checked's
// environment filtering ever breaks, these fixtures still build, so the failure
// shows up in the assertion instead of as a confusing setup error).

// --- ResolveFull: the "did it resolve at all" decision (.ps1:345-348) ---

// TestResolveFullFromShortPrefix: a 7-char prefix resolves to the full id. This
// is the normalisation GAP-008 relies on — both sides come out in one spelling
// before any comparison happens.
func TestResolveFullFromShortPrefix(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	got, ok := sha.ResolveFull(repo, full[:7])
	if !ok {
		t.Fatalf("ResolveFull(%q) ok=false; want true (short prefix names the commit)", full[:7])
	}
	if got != full {
		t.Errorf("ResolveFull(%q) = %q; want %q (full id)", full[:7], got, full)
	}
}

// TestResolveFullUppercase: uppercase hex is accepted by git and comes back
// lowercase. This is why ResolveFull must NOT lowercase its input blindly — it
// also has to accept ref names, which are case-sensitive.
func TestResolveFullUppercase(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	got, ok := sha.ResolveFull(repo, strings.ToUpper(full))
	if !ok {
		t.Fatalf("ResolveFull(uppercase) ok=false; want true")
	}
	if got != full {
		t.Errorf("ResolveFull(uppercase) = %q; want lowercase %q", got, full)
	}
}

// TestResolveFullRefName: ref names resolve too (the mainline side of the
// comparison is a REF, e.g. "refs/heads/main" — check-progress.ps1:345). A ref
// spelled with uppercase must keep its spelling: lowercasing it would name a
// different (usually non-existent) ref.
func TestResolveFullRefName(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	got, ok := sha.ResolveFull(repo, "refs/heads/main")
	if !ok {
		t.Fatalf("ResolveFull(refs/heads/main) ok=false; want true")
	}
	if got != full {
		t.Errorf("ResolveFull(refs/heads/main) = %q; want %q", got, full)
	}
}

// TestResolveFullTreeIsNotACommit: a TREE id is a valid object, and
// `rev-parse --verify <tree>` exits 0 — but the page/mainline comparison is
// about commits. The `^{commit}` peel must reject it (measured on git 2.56.0:
// exit 1 for both tree and blob). Without this, "an object named the same" could
// be read as "the same commit".
func TestResolveFullTreeIsNotACommit(t *testing.T) {
	repo := initRepoWithCommit(t)
	tree := strings.TrimSpace(runGit(t, repo, "rev-parse", "HEAD^{tree}"))
	if len(tree) != 40 {
		t.Fatalf("setup: tree id %q is not 40 chars", tree)
	}
	if _, ok := sha.ResolveFull(repo, tree); ok {
		t.Errorf("ResolveFull(tree id) ok=true; want false (a tree is not a commit)")
	}
}

// TestResolveFullBlobIsNotACommit: same shape as the tree case, for a blob. Both
// are exercised because git's error text differs per object type; the exit code
// under --quiet is 1 for both, which is the only thing judged.
func TestResolveFullBlobIsNotACommit(t *testing.T) {
	repo := initRepoWithCommit(t)
	blob := strings.TrimSpace(runGitStdin(t, repo, "hi\n", "hash-object", "-w", "--stdin"))
	if _, ok := sha.ResolveFull(repo, blob); ok {
		t.Errorf("ResolveFull(blob id) ok=true; want false (a blob is not a commit)")
	}
}

// TestResolveFullInvalidHex40: a 40-char string that is not hex never reaches
// git as a valid object name. This is a fail-closed assertion on the PAYLOAD:
// ResolveFull must not hand back whatever git printed just because the exit code
// was 0. (The .ps1 is immune by construction — its captured SHA is already
// regex-constrained to hex — and the Go side keeps that property.)
func TestResolveFullInvalidHex40(t *testing.T) {
	repo := initRepoWithCommit(t)
	if _, ok := sha.ResolveFull(repo, strings.Repeat("z", 40)); ok {
		t.Error(`ResolveFull(40 × "z") ok=true; want false`)
	}
}

// TestResolveFullEmpty: an empty id is rejected before spawning git. ("Nothing
// given" must never resolve — and an empty argument would otherwise be read by
// rev-parse as "no revision".)
func TestResolveFullEmpty(t *testing.T) {
	repo := initRepoWithCommit(t)
	if _, ok := sha.ResolveFull(repo, ""); ok {
		t.Error(`ResolveFull("") ok=true; want false`)
	}
}

// TestResolveFullUnknownID: a well-formed but non-existent object id does not
// resolve (the canary input, shape-identical to a real id).
func TestResolveFullUnknownID(t *testing.T) {
	repo := initRepoWithCommit(t)
	if _, ok := sha.ResolveFull(repo, strings.Repeat("0", 40)); ok {
		t.Error("ResolveFull(all-zero id) ok=true; want false")
	}
}

// --- EqualFull: the pure comparison of two resolved ids ---

// TestEqualFull covers the comparison itself, with the failure modes that would
// each be a silent pass if the guard trusted empty/prefix values. None of these
// need a repo: EqualFull is the decision AFTER resolution.
func TestEqualFull(t *testing.T) {
	a := strings.Repeat("a", 40)
	b := strings.Repeat("b", 40)
	cases := []struct {
		name string
		a, b string
		want bool
	}{
		{"same", a, a, true},
		{"different", a, b, false},
		{"empty-both", "", "", false},                        // never "in sync" by absence
		{"empty-left", "", a, false},                         // one side unresolved
		{"empty-right", a, "", false},                        // one side unresolved
		{"prefix-vs-full", a[:7], a, false},                  // GAP-008: no prefix matching
		{"uppercase-vs-lower", strings.ToUpper(a), a, false}, // resolved ids are lowercase by construction
		{"non-hex", strings.Repeat("z", 40), strings.Repeat("z", 40), false},
		{"short-and-long", a[:39], a, false},
		// Two VALID full ids sharing the first 7 chars must still compare
		// unequal. Without this case a "compare by prefix" mutant on the full-id
		// path survives (measured: it did, before this case was added).
		{"same-7-prefix", "abcdef1" + strings.Repeat("a", 33), "abcdef1" + strings.Repeat("b", 33), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := sha.EqualFull(c.a, c.b); got != c.want {
				t.Errorf("EqualFull(%q, %q) = %v; want %v", c.a, c.b, got, c.want)
			}
		})
	}
}

// --- Compare: the convenience wrapper (both sides resolved, then compared) ---

// TestCompareShortPrefixAndFullIDMatch: a short prefix and the full id name the
// same commit → Compare returns true. This is the positive GAP-008 case: any
// two spellings of the same commit match.
func TestCompareShortPrefixAndFullIDMatch(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	short := full[:7]
	if !sha.Compare(repo, short, full) {
		t.Errorf("Compare(%q, %q) = false; want true (same commit, different spellings)", short, full)
	}
	if !sha.Compare(repo, full, short) {
		t.Errorf("Compare(%q, %q) = false; want true (symmetric)", full, short)
	}
}

// TestCompareFakeSuffix is the CRITICAL GAP-008 negative test: a 40-char string
// whose first 7 chars are a real commit's short id, but whose remaining 33
// chars are fake, is NOT the same commit. Prefix comparison would call them
// equal; resolving to full ids correctly reports a mismatch (the fake 40-char
// string does not resolve → Compare returns false).
func TestCompareFakeSuffix(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	short := full[:7]
	// Build a 40-char string: real 7-char prefix + fake suffix (zeros). This is
	// NOT a real object id (almost certainly — the collision space is tiny).
	fake := short + strings.Repeat("0", 40-len(short))
	if len(fake) != 40 {
		t.Fatalf("setup: fake len=%d want 40", len(fake))
	}
	if fake == full {
		t.Skipf("fake %q accidentally equals full id %q — vanishingly unlikely; skip", fake, full)
	}
	// Compare(real full, fake 40-char) MUST be false: the fake does not resolve.
	if sha.Compare(repo, full, fake) {
		t.Errorf("GAP-008: Compare(%q, %q) = true; want false (fake suffix must not match via prefix)",
			full, fake)
	}
	// And the symmetric direction.
	if sha.Compare(repo, fake, full) {
		t.Errorf("GAP-008: Compare(%q, %q) = true; want false (symmetric)", fake, full)
	}
}

// TestCompareBothFake: two non-existent SHAs → both fail to resolve → false.
func TestCompareBothFake(t *testing.T) {
	repo := initRepoWithCommit(t)
	if sha.Compare(repo, "deadbeef", "feedface") {
		t.Error("Compare(two non-existent SHAs) = true; want false")
	}
}

// TestCompareUppercaseSHA: an uppercase SHA resolves to the same commit as its
// lowercase form (git object ids are case-insensitive on input; rev-parse
// outputs lowercase).
func TestCompareUppercaseSHA(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	upper := strings.ToUpper(full)
	if !sha.Compare(repo, full, upper) {
		t.Errorf("Compare(%q, %q) = false; want true (case-insensitive SHA input)", full, upper)
	}
}

// TestCompareEmptyRepo: an empty repo string → both sides fail → false
// (defensive; the caller should not call Compare with an empty repo).
func TestCompareEmptyRepo(t *testing.T) {
	if sha.Compare("", "abc", "abc") {
		t.Error("Compare(empty repo, ...) = true; want false")
	}
}

// TestCompareDifferentCommits: two distinct commits → false, even though both
// resolve. Guards against an implementation that returns "both resolved ⇒ true".
func TestCompareDifferentCommits(t *testing.T) {
	repo := initRepoWithCommit(t)
	full1 := revParseHead(t, repo)
	mustGit(t, repo, "commit", "-q", "--allow-empty", "-m", "second")
	full2 := revParseHead(t, repo)
	if full1 == full2 {
		t.Fatalf("setup: two commits have same id %q", full1)
	}
	if sha.Compare(repo, full1, full2) {
		t.Errorf("Compare(two distinct commits) = true; want false")
	}
}

// TestCompareTreeAgainstCommit: a tree id resolves as an object but not as a
// commit, so comparing it with the commit it was peeled from is a MISMATCH.
// This is the end-to-end form of the `^{commit}` requirement.
func TestCompareTreeAgainstCommit(t *testing.T) {
	repo := initRepoWithCommit(t)
	full := revParseHead(t, repo)
	tree := strings.TrimSpace(runGit(t, repo, "rev-parse", "HEAD^{tree}"))
	if sha.Compare(repo, full, tree) {
		t.Errorf("Compare(commit, its tree) = true; want false")
	}
}

// --- A git that exits 0 with junk on stdout (THE ONE RULE's residual) ---

// TestResolveFullShimExitZeroWithJunk is the Go-side twin of the V13 case that
// check-progress.ps1:36-39 records: a shim that PRINTS something arbitrary and
// exits 0. If the payload were trusted, that junk would be returned as a "full
// commit id" and then compared — the "equal garbage ⇒ in sync" silent path.
//
// The .ps1 is immune by construction: its captured SHA is already constrained
// by the HTML regex to hex. ResolveFull keeps that property by shape-checking
// the payload (fullIDRe). What this test ALSO measures is the gap that remains:
// a shim printing a WELL-FORMED 40-hex constant passes ResolveFull — the exit
// code says "resolved", and no pure function of the output can tell otherwise.
// That gap is closed upstream by Probe + Canary (check-progress.ps1:246-269),
// which force git to return different exit codes for different inputs, and
// nothing below that layer is trusted.
func TestResolveFullShimExitZeroWithJunk(t *testing.T) {
	repo := initRepoWithCommit(t)
	dir := writeShim(t, "git", `echo "not-a-sha-at-all"; exit 0`)
	prependPath(t, dir)

	if got, ok := sha.ResolveFull(repo, "HEAD"); ok {
		t.Errorf("ResolveFull under exit-0 junk shim: ok=true, id=%q; want false (payload is not an id)", got)
	}
	if sha.Compare(repo, "HEAD", "HEAD^{commit}") {
		t.Error("Compare under exit-0 junk shim: true; want false (junk must not compare equal)")
	}
}

// TestResolveFullShimAlways128 documents the OTHER half of the same V13 shape:
// a shim that always exits 128 while printing a constant. Both sides "resolve"
// to nothing, so EqualFull/Compare must NOT call them equal — "no resolution"
// is never "in sync".
func TestResolveFullShimAlways128(t *testing.T) {
	repo := initRepoWithCommit(t)
	dir := writeShim(t, "git", `echo "constant"; exit 128`)
	prependPath(t, dir)

	if _, ok := sha.ResolveFull(repo, "HEAD"); ok {
		t.Error("ResolveFull under always-128 shim: ok=true; want false")
	}
	if sha.Compare(repo, "HEAD", "refs/heads/main") {
		t.Error("Compare under always-128 shim: true; want false (equal garbage is not 'in sync')")
	}
}

// --- helpers ---

// writeShim installs an executable POSIX sh on PATH, named `name`, that does
// nothing but run the given shell body. On Windows (no sh) it skips: the
// documented failure mode is a POSIX shim, and pretending to test it with a
// .bat would be a different (and unmeasured) shape.
//
// The shim is installed in its OWN directory, which is prepended to PATH (see
// prependPath), so `git` resolves to the shim while everything else still
// resolves normally. t.Setenv restores the original PATH at test end.
func writeShim(t *testing.T, name, body string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("POSIX sh shim: not applicable on windows")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, name)
	script := "#!/bin/sh\n" + body + "\n"
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir
}

// prependPath puts dir at the FRONT of PATH for the duration of the test.
func prependPath(t *testing.T, dir string) {
	t.Helper()
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func initRepoWithCommit(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	mustGit(t, dir, "init", "-q")
	mustGit(t, dir, "config", "user.email", "test@example.com")
	mustGit(t, dir, "config", "user.name", "Test")
	mustGit(t, dir, "symbolic-ref", "HEAD", "refs/heads/main")
	mustGit(t, dir, "commit", "-q", "--allow-empty", "-m", "init")
	return dir
}

func revParseHead(t *testing.T, dir string) string {
	t.Helper()
	return strings.TrimSpace(runGit(t, dir, "rev-parse", "HEAD"))
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

// runGitStdin runs git with stdin so a blob can be written without a worktree
// file (keeps the fixture a pure object store).
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

func mustGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	c := exec.Command("git", args...)
	c.Dir = dir
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git %v in %s: %v: %s", args, dir, err, out)
	}
}
