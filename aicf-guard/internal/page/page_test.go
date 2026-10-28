package page_test

import (
	"os"
	"path/filepath"
	"testing"

	"aicf-guard/internal/page"
)

// TestReadHead covers every HTML shape the .ps1 regex must tolerate (ADR
// §1.3.6): no attributes, b[class], b[style], div[class], whitespace both
// sides, uppercase SHA (GAP-008 — must still match, not fall through to
// silence). Plus the negative cases: missing file, no marker, <span> restructure
// (GAP-025 residual — silent, pinned), and the {7,40} length bounds.
func TestReadHead(t *testing.T) {
	cases := []struct {
		name    string
		html    string
		wantSHA string
		wantOK  bool
	}{
		// --- Positive shapes (tolerate presentation tweaks, GAP-025 partial fix) ---
		{"no-attr", `<html><div>head <b>deadbeef</b></div></html>`, "deadbeef", true},
		{"b-class", `<div>head <b class="v">deadbeef</b></div>`, "deadbeef", true},
		{"b-style", `<div>head <b style="color:red">deadbeef</b></div>`, "deadbeef", true},
		{"b-class-and-style", `<div>head <b class="v" style="x:1">deadbeef</b></div>`, "deadbeef", true},
		{"div-class", `<div class="bar">head <b>deadbeef</b></div>`, "deadbeef", true},
		{"div-id", `<div id="status">head <b>deadbeef</b></div>`, "deadbeef", true},
		{"div-and-b-attrs", `<div class="x" id="y">head <b class="z" style="w">deadbeef</b></div>`, "deadbeef", true},
		{"whitespace-both-sides", `<div>  head <b>  deadbeef  </b></div>`, "deadbeef", true},
		{"whitespace-and-newlines", "<div>\n\thead\n\t<b>\n\tdeadbeef\n\t</b>\n</div>", "deadbeef", true},
		{"uppercase-sha", `<div>head <b>DEADBEEF</b></div>`, "DEADBEEF", true},
		{"mixed-case-sha", `<div>head <b>DeadBeef</b></div>`, "DeadBeef", true},
		{"full-40-sha", `<div>head <b>` + fullSHA + `</b></div>`, fullSHA, true},
		{"short-7-min", `<div>head <b>abc1234</b></div>`, "abc1234", true},
		{"sha-in-context", `<html><body><div>other</div><div>head <b>deadbeef</b></div><div>more</div></body></html>`, "deadbeef", true},

		// --- Negative shapes (SILENT — same silence as .ps1) ---
		{"span-restructure", `<span>head <b>deadbeef</b></span>`, "", false},       // GAP-025 residual (pinned, not fixed)
		{"no-marker", `<html><body>nothing here</body></html>`, "", false},         // restructured beyond recognition
		{"head-without-b", `<div>head deadbeef</div>`, "", false},                  // missing <b>
		{"b-without-div", `<b>deadbeef</b>`, "", false},                            // missing <div>
		{"too-short-6", `<div>head <b>abc123</b></div>`, "", false},                // 6 chars, below {7,40}
		{"too-long-41", `<div>head <b>` + fullSHA + "x" + `</b></div>`, "", false}, // 41 chars, above {7,40}
		{"non-hex", `<div>head <b>zzzzzzz</b></div>`, "", false},                   // 7 non-hex chars
		{"empty-b", `<div>head <b></b></div>`, "", false},                          // empty <b>
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := filepath.Join(t.TempDir(), "page.html")
			if err := os.WriteFile(f, []byte(c.html), 0o644); err != nil {
				t.Fatal(err)
			}
			got, ok := page.ReadHead(f)
			if ok != c.wantOK {
				t.Errorf("ok=%v want %v; sha=%q (html=%q)", ok, c.wantOK, got, c.html)
				return
			}
			if ok && got != c.wantSHA {
				t.Errorf("sha=%q want %q (html=%q)", got, c.wantSHA, c.html)
			}
			if !ok && got != "" {
				t.Errorf("on miss, sha should be empty; got %q (html=%q)", got, c.html)
			}
		})
	}
}

// TestReadHeadMissingFile: a non-existent path → ("", false), SILENTLY. This is
// the "not initialised yet" case (AGENTS.md §5: a missing page is not a fault).
func TestReadHeadMissingFile(t *testing.T) {
	got, ok := page.ReadHead(filepath.Join(t.TempDir(), "does-not-exist.html"))
	if ok {
		t.Error("missing file: ok=true want false")
	}
	if got != "" {
		t.Errorf("missing file: sha=%q want empty", got)
	}
}

// TestReadHeadUnreadableFile: a path that exists but cannot be read (permission
// denied) → ("", false), SILENTLY. os.ReadFile returns an error; ReadHead treats
// any read error as "no criterion applies" (same as missing file).
func TestReadHeadUnreadableFile(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("running as root — permission bits don't deny root; skip unreadable-file test")
	}
	f := filepath.Join(t.TempDir(), "noperm.html")
	if err := os.WriteFile(f, []byte(`<div>head <b>deadbeef</b></div>`), 0o000); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(f, 0o644) // restore so t.TempDir cleanup can remove it
	got, ok := page.ReadHead(f)
	if ok {
		t.Error("unreadable file: ok=true want false")
	}
	if got != "" {
		t.Errorf("unreadable file: sha=%q want empty", got)
	}
}

// TestReadHeadMultipleMarkers: if the page has multiple markers, FindSubmatch
// returns the FIRST. (The .ps1 uses [regex]::Match which also finds the first.)
// This pins the behaviour so a future change to FindAll doesn't silently alter it.
//
// The markers must be VALID hex to exercise this at all: this test first used
// `first1` / `second2`, which are 7 chars but not hexadecimal, so neither could
// match and ReadHead correctly returned ("", false) — the test was wrong, not
// the package (a hex-only pair is what the .ps1 would also have matched).
// TestReadHeadNonHexMarker below pins that distinction so it cannot come back.
func TestReadHeadMultipleMarkers(t *testing.T) {
	html := `<div>head <b>deadbee1</b></div><div>head <b>deadbee2</b></div>`
	f := filepath.Join(t.TempDir(), "page.html")
	if err := os.WriteFile(f, []byte(html), 0o644); err != nil {
		t.Fatal(err)
	}
	got, ok := page.ReadHead(f)
	if !ok {
		t.Fatal("ok=false want true (multiple markers should match the first)")
	}
	if got != "deadbee1" {
		t.Errorf("sha=%q want deadbee1 (first match)", got)
	}
}

// TestReadHeadNonHexMarker: a 7-CHARACTER token that is not hexadecimal is not a
// SHA and must NOT match — the same answer check-progress.ps1 gives (its regex
// carries the same [0-9a-fA-F]{7,40} class). Measured: the earlier version of
// TestReadHeadMultipleMarkers used exactly this shape and read the miss as a
// regression against the first-match claim.
func TestReadHeadNonHexMarker(t *testing.T) {
	html := `<div>head <b>first1</b></div><div>head <b>second2</b></div>`
	f := filepath.Join(t.TempDir(), "page.html")
	if err := os.WriteFile(f, []byte(html), 0o644); err != nil {
		t.Fatal(err)
	}
	got, ok := page.ReadHead(f)
	if ok {
		t.Errorf("ok=true sha=%q want false (non-hex tokens are not SHAs)", got)
	}
}

// TestReadHeadSkipsMalformedFirstMarker: the match is the first WELL-FORMED
// marker, NOT simply the first marker. A malformed first marker (`<b></b>`,
// `<b>()</b>`, `<b>abc</b>`) cannot match at all, so the regex engine advances
// and the SECOND marker is returned. The .ps1's [regex]::Match runs the same
// engine over the same pattern, so it takes the same branch — this is shared
// behaviour, not a Go-side choice.
//
// Why it is worth pinning: a page carrying two status bars is already a D4
// smell (two copies of one fact), and this case shows the guard would then
// enforce the SECOND one while a reader's eye lands on the first. Naming the
// behaviour here means a future "first wins" rewrite has to do it deliberately.
func TestReadHeadSkipsMalformedFirstMarker(t *testing.T) {
	cases := []struct{ name, html string }{
		{"empty-b", `<div>head <b></b></div><div>head <b>deadbee2</b></div>`},
		{"parens", `<div>head <b>()</b></div><div>head <b>deadbee2</b></div>`},
		{"too-short", `<div>head <b>abc</b></div><div>head <b>deadbee2</b></div>`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := filepath.Join(t.TempDir(), "page.html")
			if err := os.WriteFile(f, []byte(c.html), 0o644); err != nil {
				t.Fatal(err)
			}
			got, ok := page.ReadHead(f)
			if !ok || got != "deadbee2" {
				t.Errorf("ReadHead = (%q,%v); want (\"deadbee2\",true) — malformed marker is skipped, not returned", got, ok)
			}
		})
	}
}

// --- ReadPageName: the pointer file's three states (.ps1:199-206) ---

func TestReadPageNameAbsentUsesDefault(t *testing.T) {
	// Not initialised yet: no fault, default name. This is the silent case.
	got := page.ReadPageName(filepath.Join(t.TempDir(), "progress-page.txt"))
	if got.Fault {
		t.Error("absent pointer: Fault=true; want false (absent = not initialised, not a fault)")
	}
	if got.Name != page.DefaultPageName {
		t.Errorf("Name=%q want %q", got.Name, page.DefaultPageName)
	}
}

func TestReadPageNameReadsTrimmedName(t *testing.T) {
	// The pointer is one line with a trailing newline; the name must come back
	// without the surrounding whitespace.
	p := filepath.Join(t.TempDir(), "progress-page.txt")
	if err := os.WriteFile(p, []byte("  status-2026.html\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := page.ReadPageName(p)
	if got.Fault {
		t.Error("Fault=true; want false")
	}
	if got.Name != "status-2026.html" {
		t.Errorf("Name=%q want %q (trimmed)", got.Name, "status-2026.html")
	}
}

func TestReadPageNameEmptyIsFault(t *testing.T) {
	// Exists but yields nothing → FAULT (GAP-002: this is what the old silent
	// fallback did wrong — the guard would watch a file nobody named).
	for _, content := range []string{"", "\n", "   \n\t\n"} {
		p := filepath.Join(t.TempDir(), "progress-page.txt")
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		got := page.ReadPageName(p)
		if !got.Fault {
			t.Errorf("content=%q: Fault=false; want true (pointer exists but names nothing)", content)
		}
		if got.Name != page.DefaultPageName {
			t.Errorf("content=%q: Name=%q want fallback %q", content, got.Name, page.DefaultPageName)
		}
	}
}

func TestReadPageNameUnreadableIsFault(t *testing.T) {
	// An I/O error that is NOT "not exist" (here: the path is a DIRECTORY, so
	// ReadFile fails) must be a fault, not "absent". Treating it as absent would
	// silently swap in the default name — the failure this check prevents.
	p := filepath.Join(t.TempDir(), "progress-page.txt")
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatal(err)
	}
	got := page.ReadPageName(p)
	if !got.Fault {
		t.Error("directory-as-pointer: Fault=false; want true")
	}
	if got.Name != page.DefaultPageName {
		t.Errorf("Name=%q want fallback %q", got.Name, page.DefaultPageName)
	}
}

func TestReadPageNameInnerNewlineKept(t *testing.T) {
	// Trim removes only the ENDS. A two-line pointer becomes a name containing a
	// newline — no fault, but it names no real file, so the guard lands on the
	// silent "no page" branch. Pinned so nobody "helpfully" starts splitting.
	p := filepath.Join(t.TempDir(), "progress-page.txt")
	if err := os.WriteFile(p, []byte("a.html\nb.html\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := page.ReadPageName(p)
	if got.Fault {
		t.Error("Fault=true; want false (it is a name, just not a useful one)")
	}
	if got.Name != "a.html\nb.html" {
		t.Errorf("Name=%q want %q (only the ends are trimmed)", got.Name, "a.html\nb.html")
	}
}

// TestReadPageNameStripsLeadingBOM pins GAP-047: the pointer is read by
// Get-Content -Raw in the legacy .ps1, and PowerShell strips a leading UTF-8 BOM
// while decoding. Go's os.ReadFile returns the raw bytes, and U+FEFF is not in
// unicode.IsSpace, so a pointer saved as "UTF-8 with BOM" (the default of
// Notepad / VS Code / PowerShell 5.1's Out-File — this workspace migrated from
// Windows) used to yield a name no FindPage candidate could ever match, retiring
// the guard SILENTLY on a plainly stale page.
//
// The BOM-only case is NOT the same as the name case and must stay on the fault
// branch: the pointer exists but names nothing, so the reader has to be told
// (GAP-002) rather than being given the default page by a silent fallback.
func TestReadPageNameStripsLeadingBOM(t *testing.T) {
	cases := []struct {
		name      string
		content   string
		wantName  string
		wantFault bool
	}{
		{"bom + name", "\ufeffproject-progress.html\n", "project-progress.html", false},
		{"bom + name, no newline", "\ufeffproject-progress.html", "project-progress.html", false},
		{"bom + spaces + name", "\ufeff  status-2026.html \r\n", "status-2026.html", false},
		{"two boms strip only the first", "\ufeff\ufeffx.html", "\ufeffx.html", false},
		{"bom only", "\ufeff", page.DefaultPageName, true},
		{"bom + whitespace only", "\ufeff \n", page.DefaultPageName, true},
		// Parity reasoning (not measured here — no PowerShell on this machine):
		// Get-Content detects the BOM only at byte offset 0, so a BOM after
		// whitespace is decoded as an ordinary U+FEFF and stays in the name
		// (which then names no real file).
		{"whitespace before bom is kept", " \ufeffx.html", "\ufeffx.html", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := filepath.Join(t.TempDir(), "progress-page.txt")
			if err := os.WriteFile(p, []byte(c.content), 0o644); err != nil {
				t.Fatal(err)
			}
			got := page.ReadPageName(p)
			if got.Fault != c.wantFault {
				t.Errorf("Fault=%v want %v (content=%q)", got.Fault, c.wantFault, c.content)
			}
			if got.Name != c.wantName {
				t.Errorf("Name=%q want %q (content=%q)", got.Name, c.wantName, c.content)
			}
		})
	}
}

const fullSHA = "0123456789abcdef0123456789abcdef01234567"
