// Package progress is the Go port of .claude/hooks/check-progress.ps1 (a Claude
// Code Stop hook): the progress page must not lag the MAINLINE.
//
// # The contract being preserved
//
// The exit code / stdout / stderr contract is a PUBLISHED one — the hook
// configuration and the D3 self-test ruler both depend on it (ADR-001 §1.2,
// §6.1). It is reproduced branch for branch, INCLUDING the branches that
// deliberately say nothing:
//
//	exit 0 + empty stdout   → allow the turn to end
//	exit 0 + {"decision":"block","reason":…} (one compressed line)
//	                        → the page lags; feed the reason back to the model
//	exit 1 + stderr         → a NON-BLOCKING notice the user must see
//	                          (git unusable, untrustworthy exit codes, bad pointer)
//	exit 0 + nothing        → one of the deliberate silences: no page, no repo,
//	                          no mainline, no HEAD marker in the page
//
// The set is {0,1}. A malformed command line is NOT a third exit code: it takes
// the exit 1 + stderr channel, because the hosts that read this hook treat any
// code outside their known set as "allow" (see Run).
//
// "It said nothing" must be the same shape as the .ps1 saying nothing (§6.1),
// which is why the silent branches are enumerated rather than collapsed.
//
// # Why the branch ORDER is load-bearing
//
// The .ps1 inspects the pointer and looks for the page BEFORE it ever runs git,
// and it reports a broken pointer BEFORE it reports a missing page. Both
// orderings are observable:
//
//   - a workspace with no page must exit 0 without running git at all — if this
//     port probed git first, a machine without git would turn "not initialised
//     yet" into a notice on every stop;
//   - a pointer that exists but names nothing is a FAULT, and it outranks "no
//     page", because with no usable name the guard cannot even tell WHICH page
//     is missing (check-progress.ps1:217-227, GAP-002).
//
// # Dependencies are injected
//
// Run takes a Deps rather than calling the shared libraries directly. That is
// what lets every branch — including the two notice branches and all four
// silences — be exercised in a sandbox, and it keeps the process-global state
// (PATH, env, cwd) out of the decision logic (ADR §2.3). Production wiring is
// DefaultDeps.
package progress

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"aicf-guard/internal/git"
	"aicf-guard/internal/mainline"
	"aicf-guard/internal/page"
	"aicf-guard/internal/sha"
	"aicf-guard/internal/workspace"
)

// Deps are the collaborators Run needs. Each field is a function so a test can
// drive the branch it cares about without building a workspace, a repo, or a
// fake git (the two notice branches in particular cannot be reached otherwise:
// a real git is either usable or the test machine is broken).
type Deps struct {
	// Resolve finds the workspace root and the repo. Workspace is set even when
	// the repo is not found (that distinction drives the notice-vs-silent split).
	Resolve func(flagWorkspace string) workspace.Result
	// Probe is the positive probe: `git --version` must exit 0.
	Probe func() bool
	// Canary is the negative canary: a MUST-FAIL input must exit non-zero.
	Canary func() bool
	// Mainline resolves the trunk ref (three-level fallback, GAP-031).
	Mainline func(repo string) mainline.Result
	// ShortRef is the short form of a ref, used ONLY in the reason string
	// (check-progress.ps1:349-350). Never a criterion; a failure here is not a
	// decision, so it returns ok=false rather than an error.
	ShortRef func(repo, ref string) (string, bool)
	// ResolveFull resolves a ref or id to a full 40-hex commit id.
	ResolveFull func(repo, id string) (string, bool)
	// ReadPageName applies the pointer-file semantics.
	ReadPageName func(pointerPath string) page.NameResult
	// FindPage locates the page among the two layout candidates.
	FindPage func(ws, name string) (string, bool)
	// ReadHead extracts the recorded SHA from the page's status bar.
	ReadHead func(path string) (string, bool)
}

// DefaultDeps wires the real shared libraries. This is the ONLY place the
// subcommand touches the outside world.
func DefaultDeps() Deps {
	return Deps{
		Resolve:      workspace.Resolve,
		Probe:        git.Probe,
		Canary:       git.Canary,
		Mainline:     mainline.Resolve,
		ShortRef:     mainline.ShortRef,
		ResolveFull:  sha.ResolveFull,
		ReadPageName: page.ReadPageName,
		FindPage:     workspace.FindPage,
		ReadHead:     page.ReadHead,
	}
}

// progName prefixes usage-error lines. Kept as a constant so the wording is
// greppable and identical across the flag paths.
const progName = "aicf-guard progress"

// Messages are copied VERBATIM from check-progress.ps1 so the two channels stay
// byte-comparable during the migration (ADR §2.5). The pointer path inside the
// first one is literal in the .ps1 too, not derived.
const (
	msgPointerFault = "进度页指针异常：.claude/progress-page.txt 存在但读不出页名（空 / 全空白 / 不可读）。守卫已回退到默认页名，可能在看一个错误的文件。"
	msgGitUnusable  = "进度页守卫未运行：PATH 上的 git 不可用（缺失或无法执行）。本轮未检查进度页是否落后。"
	msgCanaryFailed = "进度页守卫未运行：PATH 上的 git 退出码不可信（对必定失败的输入仍返回 0）。本轮未检查进度页是否落后。"
)

// reasonTemplate is check-progress.ps1:403-405 with its four interpolations
// left as %s: name, recorded, mainName, headShort.
//
// The wording is load-bearing, not cosmetic. The .ps1's own comment says the
// reason MUST name the line that was compared (GAP-031): on a feature branch,
// "currently X" points the reader at the wrong fact — the page is stale
// relative to the TRUNK, not relative to their branch tip.
const reasonTemplate = "进度页落后于主干：%s 记录的 HEAD 是 %s，而 %s 是 %s。" +
	"请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。" +
	"需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"

// Run executes the subcommand and returns the process exit code. `args` is
// everything after the subcommand name.
//
// # The return value is ALWAYS 0 or 1 — never 2
//
// This subcommand is a Stop hook, so its exit code is read by HOSTS, not by a
// human at a terminal. Neither host treats 2 as a failure: Claude Code's Stop
// event does not define it, and stop-adapter.ps1's `if ($exitCode -ne 0 -and
// $stderr)`-style handling routes anything outside its known set to `allow`
// (.agents/hooks/stop-adapter.ps1:56-74 — "若某守卫新增一个【未被覆盖】的退出码
// （如 exit 2），适配器会落到 allow 分支", self-test.ps1:1078). A `return 2`
// here therefore did not mean "loud error" — it meant "the guard silently
// allowed the turn", which is the exact failure D3 exists to prevent.
//
// So a USAGE error (bad flag, missing flag value, stray positional) takes the
// same channel as every other "the guard could not run" outcome: exit 1 +
// stderr, with wording that says it was a usage error. Exit 2 is reserved for
// the CLI layer (main.go's unknown-subcommand / no-args paths), which no hook
// calls; docs/changes/005 §十 records that boundary.
func Run(args []string, stdout, stderr io.Writer, d Deps) int {
	fs := flag.NewFlagSet("progress", flag.ContinueOnError)
	fs.SetOutput(stderr)
	wsFlag := fs.String("workspace", "", "explicit workspace root (overrides CLAUDE_PROJECT_DIR / executable / cwd discovery)")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "usage: aicf-guard progress [--workspace <path>]")
		fmt.Fprintln(fs.Output(), "")
		fmt.Fprintln(fs.Output(), "Exit 0 with no output = allow; exit 0 with a decision:block JSON = the")
		fmt.Fprintln(fs.Output(), "page lags; exit 1 with stderr = a non-blocking notice. See ADR-001 §1.2.")
	}
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0 // -h/--help already printed usage; asking for help is not an error
		}
		// flag has already complained on stderr; add the sentence that says what
		// KIND of failure this is, then stop. Do NOT return 2 — see the doc above.
		fmt.Fprintf(stderr, "%s: usage error: %v\n", progName, err)
		fmt.Fprintf(stderr, "(the guard did NOT run; run `%s --help` for usage)\n", progName)
		return 1
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "%s: usage error: unexpected argument %q\n", progName, fs.Arg(0))
		fmt.Fprintf(stderr, "(the guard did NOT run; run `%s --help` for usage)\n", progName)
		return 1
	}
	return decide(*wsFlag, stdout, stderr, d)
}

// msgWorkspaceFlagRejected is the notice for an explicit --workspace that is not
// a workspace. It is not copied from the .ps1 (there is no --workspace flag
// there): ADR §2.3 makes an explicit override AUTHORITATIVE, and an override
// that is silently discarded leaves the caller believing the guard looked where
// it was told to look. That is the "silently wrong" family (AGENTS.md §8), so it
// takes the notice channel instead of the "not initialised" silence.
const msgWorkspaceFlagRejected = "进度页守卫未运行：--workspace 指定的目录不是工作区（其中没有 .claude/ 或 .agents/）。" +
	"显式覆盖被拒绝时不会回退到自动发现——本轮未检查进度页是否落后。请检查路径，或去掉 --workspace 改用自动发现。"

// decide is the branch sequence. It returns the exit code and writes at most one
// line to exactly one channel, matching the .ps1's mutually exclusive branches.
func decide(wsFlag string, stdout, stderr io.Writer, d Deps) int {
	// --- workspace (check-progress.ps1:183-187) ---
	// Unresolvable workspace = "not initialised" — the .ps1 cannot fail here (it
	// always derives SOME directory), and what follows from a directory with no
	// `.claude/` is the pointer-absent + no-page silence. Same observable.
	wsRes := d.Resolve(wsFlag)
	if wsRes.Workspace == "" {
		// ...EXCEPT when the caller named the workspace explicitly. Discovery
		// finding nothing is "not initialised"; an explicit override finding
		// nothing is a rejected instruction, and staying silent about it would
		// make it indistinguishable from a successful run (ADR §2.3).
		if wsFlag != "" {
			fmt.Fprintln(stderr, msgWorkspaceFlagRejected)
			return 1
		}
		return 0
	}

	// --- pointer file (199-206) and page lookup (212-215) ---
	// Both happen before any git call, and the pointer fault is reported even
	// when no page was found (224-227 precedes 233).
	claudeDir := filepath.Join(wsRes.Workspace, ".claude")
	name := d.ReadPageName(filepath.Join(claudeDir, "progress-page.txt"))
	pagePath, havePage := d.FindPage(wsRes.Workspace, name.Name)

	if name.Fault {
		fmt.Fprintln(stderr, msgPointerFault)
		return 1
	}
	if !havePage {
		return 0
	}

	// --- git usability (246-250): notice, not silence and not block ---
	// Missing git means the guard CANNOT TELL whether the page lags. Blocking
	// every turn would make the framework unusable; staying silent would make a
	// dead guard look alive. So: exit 1 + stderr.
	if !d.Probe() {
		fmt.Fprintln(stderr, msgGitUnusable)
		return 1
	}
	// Negative canary (265-269): the probe demands "this MUST SUCCEED", the
	// canary demands "this MUST FAIL". Together they force git to disagree with
	// itself, which is what makes the exit code a criterion rather than an
	// assumption. A shim that always exits 0 passes the probe and dies here.
	if !d.Canary() {
		fmt.Fprintln(stderr, msgCanaryFailed)
		return 1
	}

	// --- repo (286-291) ---
	// Resolve already tried @[ws, ws/project], ws first, each gated on
	// `rev-parse --git-dir` exit 0 (GAP-009). No repo → nothing to compare.
	if wsRes.Repo == "" {
		return 0
	}
	repo := wsRes.Repo

	// --- mainline (314-340, GAP-031) ---
	// NOT the checked-out HEAD. All three levels failing (unborn repo) is the
	// same silence as "no page": the premise "the page exists and must not lag"
	// has no left-hand side.
	ml := d.Mainline(repo)
	if !ml.Ok {
		return 0
	}

	// --- mainline full id (345-348) ---
	// A separate step, and a separate silence, exactly as in the .ps1: the ref
	// resolved a moment ago, but re-resolving can still fail (a ref deleted in
	// between), and that is not "the page lags".
	headFull, ok := d.ResolveFull(repo, ml.Ref)
	if !ok || headFull == "" {
		return 0
	}

	// Short form, for the reason string ONLY — never the criterion (349-350).
	// If `--short` yields nothing, fall back to the full id so the message still
	// names a commit.
	headShort := headFull
	if s, ok := d.ShortRef(repo, ml.Ref); ok && s != "" {
		headShort = s
	}

	// --- the page's recorded SHA (352-376) ---
	// A missing marker, an unreadable page, or a <span> restructure all land
	// here and all stay SILENT (GAP-025 residual, accepted: a false alarm on
	// every stop is worse than saying nothing).
	recorded, ok := d.ReadHead(pagePath)
	if !ok {
		return 0
	}

	// --- the comparison (396-397, GAP-008) ---
	// BOTH sides are resolved to full ids and judged by exit code; the recorded
	// id failing to resolve is a LAGGING page, not a reason to fall silent.
	// Lowercasing is safe here and mirrors the .ps1: the HTML regex has already
	// constrained `recorded` to hex, and hex object ids are case-insensitive.
	recFull, ok := d.ResolveFull(repo, strings.ToLower(recorded))
	if ok && sha.EqualFull(headFull, recFull) {
		return 0
	}

	// --- block ---
	reason := buildReason(name.Name, recorded, ml.Name, headShort)
	if err := writeDecisionBlock(stdout, reason); err != nil {
		// The guard must never break a turn because it could not write. Staying
		// silent is what the .ps1's outer catch does.
		return 0
	}
	return 0
}

// buildReason fills reasonTemplate. Split out so the wording can be compared
// byte for byte against the .ps1's template without driving the whole guard.
func buildReason(name, recorded, mainName, headShort string) string {
	return fmt.Sprintf(reasonTemplate, name, recorded, mainName, headShort)
}

// writeDecisionBlock emits {"decision":"block","reason":…} as ONE compressed
// line, the shape ConvertTo-Json -Compress produces for the .ps1's ordered
// hashtable (check-progress.ps1:407).
//
// SetEscapeHTML(false) because ConvertTo-Json does not HTML-escape either; the
// default encoder turns `<`, `>` and `&` into <-style escapes, which would
// be a byte difference even for the same logical JSON.
func writeDecisionBlock(w io.Writer, reason string) error {
	payload := struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}{Decision: "block", Reason: reason}

	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	return enc.Encode(payload) // Encode appends the single trailing newline
}
