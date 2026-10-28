// Package numbers is the Go port of .claude/hooks/check-numbers.ps1
// (a Claude Code Stop hook, M1 per ADR-001): identifier numbers in
// docs/changes/ must not collide ACROSS BRANCHES.
//
// # The contract being preserved
//
// The number space of an adopter's docs/changes/NNN-*.md is shared by the
// WHOLE repo, across ALL branches. A guard that looks only at HEAD is a
// FALSE guard: it stays green while two parallel branches each pick the
// same number, and the collision only surfaces at merge time.
//
//	exit 0 + no output  -> no collision, allow the turn to end
//	exit 1 + stderr      -> a collision, OR the guard could not run
//	                        (git unusable, untrustworthy exit codes,
//	                        candidate repo / refs / tree unreadable).
//	                        NOTICE, not block: the colliding branch may be
//	                        one the current session must not rewrite.
//
// The set is {0,1}, for the same reason as progress.Run: a Stop hook host
// treats any code outside its known set as "allow", so a usage error here
// also takes exit 1 + stderr, never 2.
//
// # Branch order is load-bearing
//
//   - "No candidates" is silent, and it is decided BEFORE any git probe:
//     a workspace with no repo at all is "not initialised", not a fault
//     (GAP-020). Probing git first would turn that into a notice on every
//     stop on a machine without git.
//   - Local refs shadow remote-tracking refs of the same leaf name:
//     refs/heads/X and refs/remotes/origin/X are the SAME branch, but they
//     hold different oids whenever a local commit has not been pushed yet.
//     Unioning both raw ref sets would report docs/changes/001-*.md against
//     itself as a "cross-branch collision" on every unpushed commit.
//   - A number is a collision when it names MORE THAN ONE DISTINCT
//     (path, blob oid) pair: same path with a different oid on another
//     branch is an add/add conflict at merge time, and two paths that
//     merely share content are still two distinct files. The SAME
//     (path, oid) seen on several branches is one file, not a collision.
//   - Keys are case-SENSITIVE throughout (branch leaves and the (path, oid)
//     sets): branch names differing only in case are two branches on a
//     case-sensitive filesystem, and NNN-Alpha.md vs NNN-alpha.md are two
//     distinct files.
//
// Every git call goes through git.Checked and is judged by exit code only;
// output is a PAYLOAD, never the criterion (THE ONE RULE, ADR-001 §1.3).
package numbers

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"aicf-guard/internal/git"
	"aicf-guard/internal/workspace"
)

const progName = "aicf-guard numbers"

// Messages are copied from check-numbers.ps1 via its single Write-Notice
// channel: "编号守卫未运行：" + text + "本轮未检查编号撞车。", so the two
// channels stay comparable during the migration (ADR §2.5).
const (
	msgEnumFailed   = "编号守卫未运行：无法枚举工作区目录（枚举失败 ≠ 没有候选仓）。本轮未检查编号撞车。"
	msgGitUnusable  = "编号守卫未运行：PATH 上的 git 不可用（缺失或无法执行）。本轮未检查编号撞车。"
	msgCanaryFailed = "编号守卫未运行：PATH 上的 git 退出码不可信（对必定失败的输入仍返回 0）。本轮未检查编号撞车。"
	msgWorkspaceBad = "编号守卫未运行：--workspace 指定的目录不是工作区（其中没有 .claude/ 或 .agents/）。本轮未检查编号撞车。"
)

// Run executes the subcommand and returns the process exit code. args is
// everything after the subcommand name.
func Run(args []string, stdout, stderr io.Writer) int {
	_ = stdout // numbers never writes to stdout: silence IS the success signal.
	fs := flag.NewFlagSet("numbers", flag.ContinueOnError)
	fs.SetOutput(stderr)
	wsFlag := fs.String("workspace", "", "explicit workspace root (overrides CLAUDE_PROJECT_DIR / executable / cwd discovery)")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "usage: aicf-guard numbers [--workspace <path>]")
		fmt.Fprintln(fs.Output(), "")
		fmt.Fprintln(fs.Output(), "Exit 0 with no output = no collision; exit 1 with stderr = a collision")
		fmt.Fprintln(fs.Output(), "or a notice that the guard could not run. See ADR-001 §1.2.")
	}
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		fmt.Fprintf(stderr, "%s: usage error: %v\n", progName, err)
		fmt.Fprintf(stderr, "(the guard did NOT run; run `%s --help` for usage)\n", progName)
		return 1
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "%s: usage error: unexpected argument %q\n", progName, fs.Arg(0))
		fmt.Fprintf(stderr, "(the guard did NOT run; run `%s --help` for usage)\n", progName)
		return 1
	}
	return check(*wsFlag, stderr)
}

// check is the branch sequence from check-numbers.ps1, in the same order.
func check(wsFlag string, stderr io.Writer) int {
	wsRes := workspace.Resolve(wsFlag)
	if wsRes.Workspace == "" {
		if wsFlag != "" {
			fmt.Fprintln(stderr, msgWorkspaceBad)
			return 1
		}
		return 0
	}
	ws := wsRes.Workspace

	// Candidates = the workspace root ITSELF, plus EVERY child holding a
	// `.git` entry. The root matters under the self-hosted layout (the repo
	// IS the workspace root); children matter under target / carrying
	// layouts. A failed enumeration is NOT "no candidates" (GAP-020).
	projects, err := candidates(ws)
	if err != nil {
		fmt.Fprintln(stderr, msgEnumFailed)
		return 1
	}
	// Only NOW is "no candidates" a fact rather than a failure to look.
	if len(projects) == 0 {
		return 0
	}

	if !git.Probe() {
		fmt.Fprintln(stderr, msgGitUnusable)
		return 1
	}
	if !git.Canary() {
		fmt.Fprintln(stderr, msgCanaryFailed)
		return 1
	}

	var collisions []string
	for _, proj := range projects {
		leaf := filepath.Base(proj)
		if git.Checked("-C", proj, "rev-parse", "--git-dir").Exit != 0 {
			fmt.Fprintf(stderr, "编号守卫未运行：候选仓库不可用（%s）。本轮未检查编号撞车。\n", leaf)
			return 1
		}
		refsRes := git.Checked("-C", proj, "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes")
		if refsRes.Exit != 0 {
			fmt.Fprintf(stderr, "编号守卫未运行：无法枚举分支（%s）。本轮未检查编号撞车。\n", leaf)
			return 1
		}
		refs := collapseRefs(splitLines(refsRes.Text))
		if len(refs) == 0 {
			continue
		}
		byNum := map[string]map[string]struct{}{}
		for _, ref := range refs {
			tree := git.Checked("-C", proj, "ls-tree", "-r", "-z", ref, "--", "docs/changes/")
			if tree.Exit != 0 {
				fmt.Fprintf(stderr, "编号守卫未运行：无法列出分支树（%s / %s）。本轮未检查编号撞车。\n", leaf, ref)
				return 1
			}
			for _, rec := range strings.Split(tree.Text, "\x00") {
				if rec == "" {
					continue
				}
				num, identity, ok := parseLsTreeRecord(rec)
				if !ok {
					continue
				}
				set, ok := byNum[num]
				if !ok {
					set = map[string]struct{}{}
					byNum[num] = set
				}
				set[identity] = struct{}{}
			}
		}
		collisions = append(collisions, formatCollisions(leaf, byNum)...)
	}
	if len(collisions) == 0 {
		return 0
	}

	msg := "编号跨分支撞车（docs/changes/）：同一编号在多条分支上命名了不同文件——\n" +
		strings.Join(collisions, "\n") +
		"\n编号空间是全仓、跨分支共享的；只查 HEAD 的守卫看不见它（AGENTS.md §6.1）。" +
		"\n选号请查全部分支并集，别只看当前检出。"
	fmt.Fprintln(stderr, msg)
	return 1
}

// candidates returns the workspace root itself (if it holds a `.git` entry)
// followed by every immediate child directory holding a `.git` entry, in
// directory order. An enumeration error is returned, not an empty list.
func candidates(ws string) ([]string, error) {
	var projects []string
	if _, err := os.Stat(filepath.Join(ws, ".git")); err == nil {
		projects = append(projects, ws)
	}
	entries, err := os.ReadDir(ws)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		child := filepath.Join(ws, e.Name())
		if _, err := os.Stat(filepath.Join(child, ".git")); err == nil {
			projects = append(projects, child)
		}
	}
	return projects, nil
}

// splitLines splits git output on newlines, dropping empty lines.
func splitLines(text string) []string {
	var out []string
	for _, line := range strings.Split(text, "\n") {
		if line != "" {
			out = append(out, line)
		}
	}
	return out
}

// collapseRefs folds local refs with their remote-tracking counterparts:
// key by BRANCH LEAF NAME, local first so it shadows the remote of the same
// name. refs/remotes/<remote>/HEAD is a symbolic alias, not a branch, and
// is skipped. Order is preserved (local refs first, then remotes, each in
// the order for-each-ref returned them) so collision output is stable.
func collapseRefs(refs []string) []string {
	sorted := make([]string, len(refs))
	copy(sorted, refs)
	sort.SliceStable(sorted, func(i, j int) bool {
		return strings.HasPrefix(sorted[i], "refs/heads/") && !strings.HasPrefix(sorted[j], "refs/heads/")
	})
	seen := map[string]struct{}{}
	var out []string
	for _, r := range sorted {
		leaf, ok := refLeaf(r)
		if !ok || leaf == "HEAD" {
			continue
		}
		if _, dup := seen[leaf]; dup {
			continue
		}
		seen[leaf] = struct{}{}
		out = append(out, r)
	}
	return out
}

// refLeaf strips refs/heads/ or refs/remotes/<remote>/, leaving the branch
// name (which may itself contain slashes). Anything else is not a branch.
func refLeaf(ref string) (string, bool) {
	if rest, ok := strings.CutPrefix(ref, "refs/heads/"); ok {
		return rest, true
	}
	if rest, ok := strings.CutPrefix(ref, "refs/remotes/"); ok {
		// First component is the remote name; the rest is the branch.
		if _, branch, ok := strings.Cut(rest, "/"); ok && branch != "" {
			return branch, true
		}
	}
	return "", false
}

var lsTreeRecord = regexp.MustCompile(`^\S+\s+\S+\s+([0-9a-f]+)\t(.+)$`)
var numberPrefix = regexp.MustCompile(`^(\d{3})-`)

// parseLsTreeRecord parses one `ls-tree -r -z` record:
// "<mode> SP <type> SP <oid> TAB <path>". It returns the 3-digit number
// taken from the leaf filename and the identity "full-path@oid" (the
// identity is the FULL path, not the leaf: NNN-a.md under old/ is a
// different file from NNN-a.md at the top level).
func parseLsTreeRecord(rec string) (num, identity string, ok bool) {
	m := lsTreeRecord.FindStringSubmatch(rec)
	if m == nil {
		return "", "", false
	}
	oid, relPath := m[1], m[2]
	leaf := filepath.Base(relPath)
	nm := numberPrefix.FindStringSubmatch(leaf)
	if nm == nil {
		return "", "", false
	}
	return nm[1], relPath + "@" + oid, true
}

// formatCollisions renders every number whose identity set has more than
// one member, numbers sorted ascending, identities sorted. Splitting on
// the LAST '@' matters: an oid is trailing hex and can never contain one,
// while a path can.
func formatCollisions(projLeaf string, byNum map[string]map[string]struct{}) []string {
	nums := make([]string, 0, len(byNum))
	for num := range byNum {
		nums = append(nums, num)
	}
	sort.Strings(nums)
	var out []string
	for _, num := range nums {
		set := byNum[num]
		if len(set) <= 1 {
			continue
		}
		seen := make([]string, 0, len(set))
		for id := range set {
			seen = append(seen, id)
		}
		sort.Strings(seen)
		shown := make([]string, 0, len(seen))
		for _, id := range seen {
			i := strings.LastIndex(id, "@")
			p, o := id[:i], id[i+1:]
			if len(o) > 7 {
				o = o[:7]
			}
			shown = append(shown, p+" ("+o+")")
		}
		out = append(out, fmt.Sprintf("  [%s] %s : %s", projLeaf, num, strings.Join(shown, "  |  ")))
	}
	return out
}
