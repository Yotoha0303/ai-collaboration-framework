package parallel

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// Scenario is one named comparison. Make builds a FRESH sandbox in dir; both
// sides get their own (see Run).
type Scenario struct {
	// Name mirrors the .ps1 self-test cell it reproduces where one exists, so
	// the two lists can be lined up once an oracle is available.
	Name string
	// Make populates an empty directory as a workspace root and returns any
	// EXTRA environment the child needs (e.g. GIT_DIR for the hijack cell, a
	// PATH shim for the canary cell). Empty for most scenarios.
	//
	// It must be deterministic in STRUCTURE (files, refs, branch names) — commit
	// ids may differ between the two sandboxes, which is why every scenario
	// derives the page's SHA from the sandbox's OWN HEAD.
	Make func(dir string) (env []string, err error)
	// Expect is the Go side's documented outcome. Code < 0 means "not checked".
	// It is NOT the parity criterion — parity is Go vs Oracle — but asserting it
	// turns a silently-wrong Go side into an ERROR instead of a mysterious DIFF
	// (or, worse, a green run when no oracle is configured).
	Expect Expect
	// SkipReason, when non-nil and non-empty, marks the scenario as not
	// applicable on this platform (reported as SKIP, never PASS).
	SkipReason func() string
}

// Expect is a subset of the contract that is cheap to state and expensive to
// get wrong.
type Expect struct {
	Code           int
	StdoutContains []string
	StdoutEmpty    bool
	StderrContains []string
	StderrEmpty    bool
}

// check returns "" when res satisfies e, or a human-readable violation.
func (e Expect) check(res Result) string {
	if e.Code >= 0 && res.Exit != e.Code {
		return fmt.Sprintf("exit=%d want %d", res.Exit, e.Code)
	}
	if e.StdoutEmpty && res.Stdout != "" {
		return fmt.Sprintf("stdout=%q want empty", res.Stdout)
	}
	if e.StderrEmpty && res.Stderr != "" {
		return fmt.Sprintf("stderr=%q want empty", res.Stderr)
	}
	for _, want := range e.StdoutContains {
		if !strings.Contains(res.Stdout, want) {
			return fmt.Sprintf("stdout=%q must contain %q", res.Stdout, want)
		}
	}
	for _, want := range e.StderrContains {
		if !strings.Contains(res.Stderr, want) {
			return fmt.Sprintf("stderr=%q must contain %q", res.Stderr, want)
		}
	}
	return ""
}

// Scenarios is the ordered scenario list. Order follows the .ps1 ruler's A group
// (A1–A13) and then the notice/silence branches.
func Scenarios() []Scenario {
	return []Scenario{
		{
			Name: "A1 正控 页面存在+错SHA → decision:block",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n")
			},
			Expect: Expect{
				Code:           0,
				StdoutContains: []string{`"decision":"block"`, "记录的 HEAD 是 0000000", "而 main 是"},
				StderrEmpty:    true,
			},
		},
		{
			Name: "A2 对照 页面存在+SHA一致 → 静默",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				head, err := shortHead(dir)
				if err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>"+head+"</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "A3 负控 指针指向不存在页名 → 静默（GAP-002 已接受代价）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				if err := writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n"); err != nil {
					return nil, err
				}
				return nil, writePointer(dir, "no-such-page.html\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "A4 <b> 加 class 属性 → 仍 block（GAP-025 已修此格）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				return nil, writePage(dir, `<html><body><div>head <b class="v">0000000</b></div></body></html>`+"\n")
			},
			Expect: Expect{Code: 0, StdoutContains: []string{`"decision":"block"`}, StderrEmpty: true},
		},
		{
			Name: "A5 重构成 <span> → 仍静默（GAP-025 残余，故意断言）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				return nil, writePage(dir, `<html><body><div>head <span>0000000</span></div></body></html>`+"\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "A6/A7 unborn 仓 + 页面存在且写错 SHA → 静默（GAP-012 维持）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoNoCommit(dir); err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "A8 对照 同一沙箱补一次提交后 → 必须 block（证明 A7 是分支特定）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoNoCommit(dir); err != nil {
					return nil, err
				}
				if err := git(dir, "commit", "-q", "--allow-empty", "-m", "seed"); err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutContains: []string{`"decision":"block"`}, StderrEmpty: true},
		},
		{
			Name: "A9/A10 GIT_DIR 注入他仓 → 读数不被劫持，仍按本仓判定",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				// A second repo whose HEAD differs. GIT_DIR pointing at it must
				// not change what the guard reads.
				other := filepath.Join(dir, "other")
				if err := initRepoOnMain(other); err != nil {
					return nil, err
				}
				if err := git(other, "commit", "-q", "--allow-empty", "-m", "other"); err != nil {
					return nil, err
				}
				otherHead, err := shortHead(other)
				if err != nil {
					return nil, err
				}
				wsHead, err := shortHead(dir)
				if err != nil {
					return nil, err
				}
				if otherHead == wsHead {
					return nil, errors.New("setup: the two repos have the same HEAD; the hijack cell would prove nothing")
				}
				// Page records the OTHER repo's head: if GIT_DIR leaked through,
				// the guard would compare against `other` and call it in sync —
				// i.e. SILENTLY wave a stale page through (the GAP-013① defect).
				if err := writePage(dir, "<html><body><div>head <b>"+otherHead+"</b></div></body></html>\n"); err != nil {
					return nil, err
				}
				return []string{"GIT_DIR=" + filepath.Join(other, ".git")}, nil
			},
			Expect: Expect{Code: 0, StdoutContains: []string{`"decision":"block"`}, StderrEmpty: true},
		},
		{
			Name: "A12 GAP-031 特性分支 + 页面=主干 → 静默（不误报）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				mainHead, err := shortHead(dir)
				if err != nil {
					return nil, err
				}
				if err := git(dir, "checkout", "-q", "-b", "feature"); err != nil {
					return nil, err
				}
				if err := git(dir, "commit", "-q", "--allow-empty", "-m", "feature work"); err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>"+mainHead+"</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "A13 GAP-031 页面记「能解析但不在主干上」的提交 → block",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				if err := git(dir, "checkout", "-q", "-b", "feature"); err != nil {
					return nil, err
				}
				if err := git(dir, "commit", "-q", "--allow-empty", "-m", "feature work"); err != nil {
					return nil, err
				}
				branchHead, err := shortHead(dir)
				if err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>"+branchHead+"</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutContains: []string{`"decision":"block"`, "而 main 是"}, StderrEmpty: true},
		},
		{
			Name: "P2 指针存在但空白 → notice（exit 1 + stderr）",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				if err := writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n"); err != nil {
					return nil, err
				}
				return nil, writePointer(dir, "   \n")
			},
			Expect: Expect{Code: 1, StdoutEmpty: true, StderrContains: []string{"进度页指针异常"}},
		},
		{
			Name: "P3 指针指向不存在页 / 无页面 → 静默",
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				return nil, writePointer(dir, "gone.html\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "P6 工作区无仓库（无 .git）→ 静默",
			Make: func(dir string) ([]string, error) {
				if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
					return nil, err
				}
				return nil, writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n")
			},
			Expect: Expect{Code: 0, StdoutEmpty: true, StderrEmpty: true},
		},
		{
			Name: "P4/P5 PATH 上的 git 恒 exit 0 → 金丝雀 notice",
			SkipReason: func() string {
				if runtime.GOOS == "windows" {
					return "POSIX sh shim; the Windows shape (.bat) is not measured"
				}
				return ""
			},
			Make: func(dir string) ([]string, error) {
				if err := initRepoOnMain(dir); err != nil {
					return nil, err
				}
				if err := writePage(dir, "<html><body><div>head <b>0000000</b></div></body></html>\n"); err != nil {
					return nil, err
				}
				shimDir := filepath.Join(dir, "shim")
				if err := os.MkdirAll(shimDir, 0o755); err != nil {
					return nil, err
				}
				if err := os.WriteFile(filepath.Join(shimDir, "git"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
					return nil, err
				}
				return []string{"PATH=" + shimDir + string(os.PathListSeparator) + os.Getenv("PATH")}, nil
			},
			Expect: Expect{Code: 1, StdoutEmpty: true, StderrContains: []string{"git 退出码不可信"}},
		},
	}
}

// --- sandbox recipe ---

// initRepoNoCommit creates <dir>/.claude + a git repo with NO commit, on `main`.
// The branch is pinned so level 2 of the mainline resolution is exercised the
// same way it is in production (this machine's init.defaultBranch is `master`).
func initRepoNoCommit(dir string) error {
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, ".claude", "progress-page.txt"), []byte("project-progress.html\n"), 0o644); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := git(dir, "init", "-q"); err != nil {
		return err
	}
	if err := git(dir, "config", "user.email", "test@example.com"); err != nil {
		return err
	}
	if err := git(dir, "config", "user.name", "Test"); err != nil {
		return err
	}
	return git(dir, "symbolic-ref", "HEAD", "refs/heads/main")
}

// initRepoOnMain is initRepoNoCommit plus one commit.
func initRepoOnMain(dir string) error {
	if err := initRepoNoCommit(dir); err != nil {
		return err
	}
	return git(dir, "commit", "-q", "--allow-empty", "-m", "seed")
}

// fixtureDate pins author and committer dates for every fixture commit.
//
// WHY this is not cosmetic: the two sandboxes are built independently, and a
// commit id covers its timestamps. Left to the wall clock, the same recipe
// yields different ids on the two sides — and the `decision:block` reason
// EMBEDS the short id (check-progress.ps1:403), so the byte comparison would
// fail for a reason that has nothing to do with the port. Deterministic dates
// make "same scenario ⇒ same ids ⇒ comparable output" true.
//
// (The .ps1's own ruler sidesteps this by writing the page from each sandbox's
// OWN HEAD and only asserting for the presence of `decision:block`. A byte
// comparison cannot do that, so the determinism has to be built in.)
const fixtureDate = "2000-01-01T00:00:00+0000"

func git(dir string, args ...string) error {
	c := exec.Command("git", args...)
	c.Dir = dir
	c.Env = append(os.Environ(),
		"GIT_AUTHOR_DATE="+fixtureDate,
		"GIT_COMMITTER_DATE="+fixtureDate,
	)
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("git %v in %s: %w: %s", args, dir, err, out)
	}
	return nil
}

func shortHead(dir string) (string, error) {
	c := exec.Command("git", "-C", dir, "rev-parse", "--short", "HEAD")
	out, err := c.Output()
	if err != nil {
		return "", fmt.Errorf("rev-parse --short HEAD in %s: %w", dir, err)
	}
	return strings.TrimSpace(string(out)), nil
}

func writePage(dir, html string) error {
	return os.WriteFile(filepath.Join(dir, "project-progress.html"), []byte(html), 0o644)
}

func writePointer(dir, content string) error {
	return os.WriteFile(filepath.Join(dir, ".claude", "progress-page.txt"), []byte(content), 0o644)
}
