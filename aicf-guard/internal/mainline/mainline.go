// Package mainline resolves the "trunk" commit for the progress-page guard
// (ADR-001 §1.3.4, GAP-031). The criterion is NOT the checked-out HEAD (a
// private, short-lived fact on a feature branch) but the MAINLINE, resolved in
// three levels; the FIRST that holds wins.
//
// # Why not HEAD (GAP-031, measured)
//
// On a feature branch the checked-out HEAD is NOT the trunk. A page recording
// the trunk's (correct) SHA was reported as "lagging" — twice in a real
// workspace — and the same false alarm reproduces on a brand-new branch with NO
// commit of its own. The three-level resolution fixes this; the reason string
// always NAMES the line that was used so a reader can tell which one.
//
// # The three levels (ADR §1.3.4)
//
//  1. Remote default branch: `git symbolic-ref refs/remotes/origin/HEAD` (must
//     exit 0 AND the result must pass `rev-parse --verify` — symbolic-ref does
//     not resolve unborn/dangling targets). Name = "origin/<branch>".
//  2. Local trunk: `refs/heads/main` (`rev-parse --verify` exit 0). Name = "main".
//  3. HEAD (explicit fallback): `rev-parse --verify HEAD^{commit}` exit 0.
//     Name = "HEAD（未找到主干）" — names the fallback so a reader can tell.
//
// All git calls go through git.Checked; the EXIT CODE is the criterion. Returns
// {Ok: false} if all three fail (unborn repo, or HEAD unreadable).
package mainline

import (
	"strings"

	"aicf-guard/internal/git"
)

// Result is the outcome of Resolve. Ref is the git ref string (e.g.,
// "refs/remotes/origin/main", "refs/heads/main", "HEAD"); Name is a
// human-readable label used in reason strings (ADR §1.3.4: reason MUST name the
// line that was compared). Ok is false if all three levels fail.
type Result struct {
	Ref  string
	Name string
	Ok   bool
}

// Resolve does the three-level fallback (ADR §1.3.4, GAP-031). See the package
// doc for the level order and the reason each level is named as it is.
func Resolve(repo string) Result {
	if repo == "" {
		return Result{}
	}
	// Level 1: remote default branch. symbolic-ref alone is NOT enough — it does
	// not resolve unborn/dangling targets, so the result must pass rev-parse
	// --verify (exit 0). Both steps judged by exit code, never output truthiness.
	oh := git.Checked("-C", repo, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
	if oh.Exit == 0 && oh.Text != "" {
		ref := oh.Text
		if git.Checked("-C", repo, "rev-parse", "--verify", "--quiet", ref+"^{commit}").Exit == 0 {
			return Result{Ref: ref, Name: stripRemotePrefix(ref), Ok: true}
		}
	}
	// Level 2: local main.
	if git.Checked("-C", repo, "rev-parse", "--verify", "--quiet", "refs/heads/main^{commit}").Exit == 0 {
		return Result{Ref: "refs/heads/main", Name: "main", Ok: true}
	}
	// Level 3: HEAD (explicit fallback, GAP-031). The name says "未找到主干" so a
	// reader of the reason string can tell this is the fallback, not the trunk.
	if git.Checked("-C", repo, "rev-parse", "--verify", "--quiet", "HEAD^{commit}").Exit == 0 {
		return Result{Ref: "HEAD", Name: "HEAD（未找到主干）", Ok: true}
	}
	return Result{}
}

// stripRemotePrefix converts "refs/remotes/origin/main" → "origin/main"
// (matching check-progress.ps1:322). Refs not starting with refs/remotes/ are
// returned unchanged (TrimPrefix is a no-op then).
func stripRemotePrefix(ref string) string {
	return strings.TrimPrefix(ref, "refs/remotes/")
}
