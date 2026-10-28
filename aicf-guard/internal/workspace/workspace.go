// Package workspace resolves the workspace root and git repo following the
// layered priority in ADR-001 §2.3. The workspace root is where `.claude/` or
// `.agents/` lives; the repo is where `.git` is.
//
// # Layered priority (strictest to loosest, ADR §2.3)
//
//  1. `--workspace` flag (explicit; selftest sandbox & unit tests).
//  2. `CLAUDE_PROJECT_DIR` env var (Claude Code sets it; Antigravity does not).
//  3. `os.Executable()` walk-up: if the binary is in <ws>/.claude/hooks/,
//     <ws>/.agents/hooks/, or <ws>/bin/, walk up to the dir containing .claude/
//     or .agents/ (preserves the .ps1 self-location robustness).
//  4. CWD walk-up (fallback; ADR §2.3 notes hook CWD is host-contract, not
//     primary — R5 keeps this as a fallback only).
//
// # Repo resolution (GAP-009)
//
// Repo candidates are @[ws, ws/project], ws FIRST. Order matters: a `project/`
// that merely exists is not a repo; if it were tried first and someone later
// ran `git init` inside it, the guard would lock onto that inner, EMPTY repo
// (measured, check-progress.ps1:275-279). A candidate must RESOLVE as a git
// repo via `git rev-parse --git-dir` exit 0 — a `.git` entry that doesn't
// resolve is not a repo.
package workspace

import (
	"os"
	"path/filepath"

	"aicf-guard/internal/git"
)

// Result is the outcome of Resolve. If Ok is false, the workspace and/or repo
// could not be resolved; callers should treat that as "not initialised" (the
// .ps1 exits silently in that case, ADR §1.2 / AGENTS.md §5).
type Result struct {
	Workspace string
	Repo      string
	Ok        bool
}

// Resolve finds the workspace root (via the 4-layer priority) and the git repo
// (via candidates @[ws, ws/project], ws first, GAP-009). Returns Ok=true iff
// BOTH resolve. If only the workspace resolves (no repo), Workspace is set and
// Repo is empty (callers can distinguish via the fields).
func Resolve(flagWorkspace string) Result {
	exePath := ""
	if exe, err := os.Executable(); err == nil {
		exePath = exe
	}
	cwd, _ := os.Getwd()
	return ResolveFrom(flagWorkspace, os.Getenv("CLAUDE_PROJECT_DIR"), exePath, cwd)
}

// ResolveFrom is Resolve with every OS-derived input passed in explicitly.
//
// It exists for two reasons:
//   - TESTS: os.Executable / os.Getwd / os.Getenv cannot be injected, so a test
//     of the layering would otherwise depend on where the test binary happens to
//     live (under `go test` that is a temp dir, whose parents may or may not
//     contain a `.claude/`).
//   - the progress subcommand: its dependency struct carries this function so
//     the whole guard can be exercised in a sandbox with no process-global
//     state (ADR §2.3 — selftest sandbox & unit tests take this route).
//
// `executable` is a PATH TO THE BINARY (not a directory); its directory is what
// the walk-up starts from. That mirrors the .ps1, whose self-location is
// `Split-Path -Parent $PSCommandPath` (check-progress.ps1:185) — the parent of
// the script, i.e. `<ws>/.claude/hooks/`. The binary's equivalent is its own
// directory, so the two are the same rule applied to the same thing.
func ResolveFrom(flagWorkspace, projectDir, executable, workingDir string) Result {
	exeDir := ""
	if executable != "" {
		exeDir = filepath.Dir(executable)
	}
	ws, ok := resolveWorkspaceLayers(flagWorkspace, projectDir, exeDir, workingDir)
	if !ok {
		return Result{}
	}
	repo := resolveRepo(ws)
	if repo == "" {
		return Result{Workspace: ws, Repo: "", Ok: false}
	}
	return Result{Workspace: ws, Repo: repo, Ok: true}
}

// FindPage locates the progress page named `name` relative to the workspace
// root, trying the same two candidates in the same order as
// check-progress.ps1:212-215:
//
//  1. <ws>/<name>             — the page is a sibling of `.claude/` (current)
//  2. <parent-of-ws>/<name>   — pre-move layout, `.claude/` inside the repo
//
// Both stay because a guard that fails closed must not go quietly dead when the
// layout shifts; the first EXISTING candidate wins.
//
// "Exists" is deliberately the loose Test-Path test, not "is a regular file":
// the .ps1 accepts a directory here too and only fails later, when it tries to
// read the page (that read error lands on the same silent branch as a missing
// page). Matching the loose test keeps the branch structure identical, so the
// Go port cannot disagree with the .ps1 about WHICH file is the page.
//
// Returns ("", false) when neither candidate exists — the caller treats that as
// "no page" and stays silent (AGENTS.md §5: not initialised is not a fault).
func FindPage(ws, name string) (string, bool) {
	if ws == "" || name == "" {
		return "", false
	}
	for _, cand := range []string{
		filepath.Join(ws, name),
		filepath.Join(filepath.Dir(ws), name),
	} {
		if _, err := os.Stat(cand); err == nil {
			return cand, true
		}
	}
	return "", false
}

// resolveWorkspaceLayers applies the 4-layer priority with EXPLICIT inputs
// (factored out for testability — tests pass synthetic values instead of
// touching os.Executable/os.Getwd/os.Getenv). Empty `flagWorkspace` skips layer
// 1 (fall-through); a non-empty flagWorkspace that is NOT a workspace FAILS
// (no fall-through) — an explicit override is authoritative, not advisory.
func resolveWorkspaceLayers(flagWorkspace, cpd, exeDir, cwd string) (string, bool) {
	if flagWorkspace != "" {
		if isWorkspace(flagWorkspace) {
			return flagWorkspace, true
		}
		return "", false
	}
	if cpd != "" && isWorkspace(cpd) {
		return cpd, true
	}
	if exeDir != "" {
		if ws := walkUpForWorkspace(exeDir); ws != "" {
			return ws, true
		}
	}
	if cwd != "" {
		if ws := walkUpForWorkspace(cwd); ws != "" {
			return ws, true
		}
	}
	return "", false
}

// isWorkspace reports whether dir looks like a workspace root (contains `.claude/`
// or `.agents/`). Used to validate flag/env candidates.
func isWorkspace(dir string) bool {
	if dir == "" {
		return false
	}
	if fi, err := os.Stat(filepath.Join(dir, ".claude")); err == nil && fi.IsDir() {
		return true
	}
	if fi, err := os.Stat(filepath.Join(dir, ".agents")); err == nil && fi.IsDir() {
		return true
	}
	return false
}

// walkUpForWorkspace starts at `start` and walks up the directory tree, returning
// the first directory that contains `.claude/` or `.agents/`. Returns "" if
// none found before the filesystem root (filepath.Dir(x) == x).
func walkUpForWorkspace(start string) string {
	dir := start
	for {
		if isWorkspace(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "" // filesystem root
		}
		dir = parent
	}
}

// resolveRepo tries candidates @[ws, ws/project] (ws first). A candidate must
// pass `git rev-parse --git-dir` exit 0 (GAP-009 — a .git entry that doesn't
// resolve is not a repo). Returns "" if none. All git calls go through
// git.Checked (THE ONE RULE).
func resolveRepo(ws string) string {
	for _, cand := range []string{ws, filepath.Join(ws, "project")} {
		if _, err := os.Stat(filepath.Join(cand, ".git")); err != nil {
			continue
		}
		if git.Checked("-C", cand, "rev-parse", "--git-dir").Exit == 0 {
			return cand
		}
	}
	return ""
}
