// Package page reads the progress page and extracts the recorded HEAD SHA from
// its status bar. The regex and the SILENCE behavior are preserved verbatim
// from check-progress.ps1:375 (ADR-001 §1.3.6, GAP-025 residual NOT fixed here).
// It also reads the one-line page-NAME pointer (check-progress.ps1:199-206).
package page

import (
	"os"
	"regexp"
	"strings"
)

// DefaultPageName is the page name used when the pointer file is ABSENT
// (check-progress.ps1:199). Absent means "not initialised yet" — not a fault —
// so the guard falls back to this name exactly as the .ps1 does.
//
// It is NOT used when the pointer exists but yields no name: that case is
// reported as a fault (see ReadPageName), because falling back there would let
// the guard watch a file nobody named (the GAP-002 defect).
const DefaultPageName = "project-progress.html"

// headRe is the SAME regex as check-progress.ps1:375. Tolerates attributes on
// <div> and <b> (and whitespace around the SHA), so a styling tweak (adding a
// class or style attribute) does NOT blind the guard — the cheapest way to go
// blind, which a styling tweak hits by accident, is removed.
//
// The RESIDUAL (GAP-025, NOT fixed in this ADR): a restructure into <span>
// still fails to match and falls SILENT. This is accepted (ADR §1.3.6); the real
// fix is P1.1's state.json (State/View separation), not a regex tweak. The
// <span> test case in page_test.go pins the residual so it is visible.
//
// One consequence of the same backtracking, pinned by
// TestReadHeadSkipsMalformedFirstMarker: the match is the FIRST WELL-FORMED
// marker, not simply the first marker. A malformed one (`<b></b>`, `<b>()</b>`)
// cannot be matched at all, so the engine advances and the SECOND marker wins.
// That is also what [regex]::Match does in the .ps1 — same engine semantics —
// and it is why two markers of one page must not be treated as "first wins".
var headRe = regexp.MustCompile(`<div[^>]*>\s*head\s*<b[^>]*>\s*([0-9a-fA-F]{7,40})\s*</b[^>]*>\s*</div[^>]*>`)

// ReadHead reads the progress page at `path` and extracts the recorded HEAD SHA
// from the `<div>head <b>SHA</b></div>` status bar. Returns (sha, true) on a
// match. Returns ("", false) — SILENTLY, matching check-progress.ps1 — if:
//   - the page is missing (not initialised, not a fault);
//   - the page is unreadable;
//   - the page contains no marker (restructured beyond recognition).
//
// The silence is deliberate (ADR §1.3.6, GAP-025 residual): a false alarm on
// every stop is worse than saying nothing. The caller distinguishes "no
// criterion applies" from "page lags" by deciding the page exists before
// relying on the SHA.
//
// The captured SHA is returned AS-IS (case-preserving). Case-normalisation
// (for comparison) is the caller's job — page.ReadHead only extracts the bytes.
func ReadHead(path string) (string, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	m := headRe.FindSubmatch(data)
	if m == nil {
		return "", false
	}
	return string(m[1]), true
}

// NameResult is the outcome of ReadPageName. Exactly one of the three states
// applies; they are mutually exclusive by construction:
//
//   - Fault == false, Name != "" — a name was read (from the pointer, or the
//     default because the pointer is absent).
//   - Fault == true             — the pointer EXISTS but yields no usable name.
//     The caller reports this to the user (exit 1 + stderr in the guard); it is
//     NOT the silent "not initialised" case (GAP-002).
//
// Name is always populated with what should be USED (the fallback default on a
// fault), so a caller that ignores Fault still looks at a real path — it just
// must not stay silent about having guessed.
type NameResult struct {
	Name  string
	Fault bool
}

// ReadPageName reads the one-line page-NAME pointer at `pointerPath`, following
// check-progress.ps1:199-206 exactly:
//
//	pointer absent                       → (DefaultPageName, no fault)
//	pointer present, trim(name) != ""    → (trim(name), no fault)
//	pointer present, trim(name) == ""    → (DefaultPageName, FAULT)
//
// i.e. a pointer that exists but names nothing (empty, all-whitespace, or
// unreadable) is a REAL fault, because the guard would otherwise silently keep
// watching a file nobody named. A pointer that is absent altogether is
// "not initialised yet", which must not alert.
//
// Unreadable is deliberately folded into the fault case rather than into
// "absent": the .ps1 tests existence with Test-Path and then reads with
// -ErrorAction SilentlyContinue, so an unreadable pointer lands on its
// `else { $pointerFault = $true }` branch. Treating an I/O error as "absent"
// would silently swap in the default page name — the exact failure this check
// exists to prevent.
//
// Trim matches PowerShell's String.Trim(): whitespace on both ends, including
// the trailing newline a one-line file carries; it does NOT split on inner
// newlines, so a two-line pointer is a name with a newline in it — which then
// fails to name any real file and lands on the silent "no page" branch, same as
// the .ps1.
func ReadPageName(pointerPath string) NameResult {
	data, err := os.ReadFile(pointerPath)
	if err != nil {
		if os.IsNotExist(err) {
			return NameResult{Name: DefaultPageName, Fault: false}
		}
		// The pointer exists (or is otherwise unreadable): a real fault.
		return NameResult{Name: DefaultPageName, Fault: true}
	}
	if name := strings.TrimSpace(string(data)); name != "" {
		return NameResult{Name: name, Fault: false}
	}
	return NameResult{Name: DefaultPageName, Fault: true}
}
