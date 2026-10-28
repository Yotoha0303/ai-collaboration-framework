// Package sha resolves git object identifiers to full 40-char lowercase hex
// COMMIT ids and compares them (ADR-001 §1.3.5, GAP-008).
//
// # Why resolve both sides
//
// Comparing the OUTPUTS of `rev-parse` as STRINGS was itself a silent path: a
// shim that always exits 128 while printing a constant made both sides equal
// garbage and the guard called it "in sync" (the V13 case). The fix is
// structural: BOTH SIDES are judged by exit code, and the outputs are compared
// only as payload. A non-zero exit on either side means the id did not resolve,
// which is a MISMATCH (a lagging page), not a reason to fall silent.
//
// Resolving to full ids (rather than prefix-matching) also defeats the
// "real prefix + fake suffix" attack: a 40-char string whose first 7 chars
// match a real commit's short id is NOT that commit, and `rev-parse --verify`
// of the full 40-char fake fails → mismatch. Prefix comparison would call them
// equal.
//
// # Shape of the API
//
// The .ps1 guard does not merely ask "are these equal" — it first resolves the
// mainline to a full id and, when that fails, takes a SILENT branch
// (check-progress.ps1:345-348) before it ever looks at the page. That is a
// different decision from "the page's id does not match", so it gets its own
// call: ResolveFull returns ("", false) and the caller decides what silence
// means. EqualFull is then the pure comparison of two already-resolved ids.
// Compare is the convenience wrapper and is implemented ON TOP of the other
// two — one implementation, so the three cannot drift apart (D4).
package sha

import (
	"regexp"

	"aicf-guard/internal/git"
)

// fullIDRe matches a full object id in the EXACT shape git prints it: 40
// lowercase hex characters, nothing else.
//
// Why the shape is checked at all (fail-closed): `Result.Text` is a payload, so
// a git that writes something unexpected to stdout on exit 0 would otherwise be
// passed along as if it were a commit id. check-progress.ps1 compares the raw
// payloads and its regex-anchored SHA makes this unreachable there; on this side
// it is one cheap assertion, and it turns "a weird git printed junk and exited
// 0" from a silent truthy value into a clean "did not resolve".
//
// `rev-parse --verify <id>^{commit}` always prints the full id (never a short
// one — the `--short` flag lives on a different call), so this cannot reject a
// legitimate result.
var fullIDRe = regexp.MustCompile(`^[0-9a-f]{40}$`)

// ResolveFull resolves `id` to a full 40-char lowercase hex COMMIT id in
// `repo`, returning ok=false if it does not resolve.
//
// "Resolves" means: `git -C <repo> rev-parse --verify --quiet <id>^{commit}`
// exited 0 AND printed exactly one full id. The exit code is the criterion
// (THE ONE RULE); the printed id is payload and is shape-checked before use.
//
// The `^{commit}` suffix is what makes this a COMMIT resolution rather than an
// object-name resolution: a tree or blob id is a perfectly valid object and
// `rev-parse --verify <tree>` would exit 0, but `^{commit}` peels to a commit
// and fails with exit 1 for anything else (measured on git 2.56.0: tree and
// blob both exit 1 under --quiet). Without the suffix a page recording a tree
// id could compare equal to a mainline that happened to be spelled the same.
//
// Inputs are NOT lowercased or otherwise rewritten: `rev-parse` accepts
// uppercase hex and prints lowercase, and it also accepts REF NAMES — a caller
// resolving "HEAD" or "refs/heads/main" must keep its spelling intact, which
// lowercasing would break (ref names are case-sensitive).
func ResolveFull(repo, id string) (string, bool) {
	if id == "" {
		return "", false
	}
	r := git.Checked("-C", repo, "rev-parse", "--verify", "--quiet", id+"^{commit}")
	if r.Exit != 0 {
		return "", false
	}
	if !fullIDRe.MatchString(r.Text) {
		return "", false
	}
	return r.Text, true
}

// EqualFull reports whether two ALREADY-RESOLVED full ids name the same commit.
// Both must be non-empty and valid full ids; an empty side is never equal to
// anything (not even another empty side), so "nothing resolved" can never be
// read as "in sync".
//
// Ids are lowercase hex by construction, so a plain == is the whole comparison
// (GAP-008: full ids on both sides, never prefixes).
func EqualFull(a, b string) bool {
	if !fullIDRe.MatchString(a) || !fullIDRe.MatchString(b) {
		return false
	}
	return a == b
}

// Compare resolves `a` and `b` in `repo` and reports whether they name the same
// commit. Returns true iff BOTH resolve AND the full ids are equal.
//
// This is the GAP-008 fix: any two spellings naming the same commit match
// (e.g., a short prefix and the full id), while a fake SHA fails to resolve and
// is correctly reported as a mismatch.
func Compare(repo, a, b string) bool {
	aFull, ok := ResolveFull(repo, a)
	if !ok {
		return false
	}
	bFull, ok := ResolveFull(repo, b)
	if !ok {
		return false
	}
	return EqualFull(aFull, bFull)
}
