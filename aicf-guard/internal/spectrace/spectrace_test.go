package spectrace

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestSpecTraceAllGreen(t *testing.T) {
	tmpDir := t.TempDir()

	// Create a spec file
	docsDir := filepath.Join(tmpDir, "docs")
	if err := os.MkdirAll(docsDir, 0755); err != nil {
		t.Fatal(err)
	}
	specFile := filepath.Join(docsDir, "spec.md")
	specContent := "# Specification\n\n- REQ-001: User authentication.\n- ADR-001: Architecture decision.\n"
	if err := os.WriteFile(specFile, []byte(specContent), 0644); err != nil {
		t.Fatal(err)
	}

	// Create an implementation file referencing REQ-001
	srcDir := filepath.Join(tmpDir, "src")
	if err := os.MkdirAll(srcDir, 0755); err != nil {
		t.Fatal(err)
	}
	codeFile := filepath.Join(srcDir, "auth.go")
	codeContent := `package src

// Implements REQ-001 for authentication.
func Authenticate(token string) bool {
	return len(token) > 0
}
`
	if err := os.WriteFile(codeFile, []byte(codeContent), 0644); err != nil {
		t.Fatal(err)
	}

	// Create a test file referencing ADR-001
	testDir := filepath.Join(tmpDir, "tests")
	if err := os.MkdirAll(testDir, 0755); err != nil {
		t.Fatal(err)
	}
	testFile := filepath.Join(testDir, "auth_test.go")
	testContent := `package tests

import "testing"

// TestAuth adheres to ADR-001.
func TestAuth(t *testing.T) {
	// tests
}
`
	if err := os.WriteFile(testFile, []byte(testContent), 0644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"--target", tmpDir}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected exit 0, got %d, stderr: %s, stdout: %s", code, stderr.String(), stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got: %s", stderr.String())
	}
}

func TestSpecTraceOrphanID(t *testing.T) {
	tmpDir := t.TempDir()

	// Spec declares REQ-999
	docsDir := filepath.Join(tmpDir, "docs")
	if err := os.MkdirAll(docsDir, 0755); err != nil {
		t.Fatal(err)
	}
	specFile := filepath.Join(docsDir, "spec.md")
	specContent := "# Requirements\n\n- REQ-999: Unimplemented requirement.\n"
	if err := os.WriteFile(specFile, []byte(specContent), 0644); err != nil {
		t.Fatal(err)
	}

	// Code has no reference to REQ-999
	srcFile := filepath.Join(tmpDir, "main.go")
	if err := os.WriteFile(srcFile, []byte("package main\n\nfunc main() {}\n"), 0644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"--target", tmpDir}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("expected exit 1 for orphan spec, got %d, stdout: %s", code, stdout.String())
	}

	if !bytes.Contains(stdout.Bytes(), []byte("ORPHAN_SPEC_ID")) {
		t.Fatalf("expected ORPHAN_SPEC_ID in stdout, got: %s", stdout.String())
	}
}

func TestSpecTraceHollowAndPlaceholder(t *testing.T) {
	tmpDir := t.TempDir()

	// Spec declares REQ-001
	specFile := filepath.Join(tmpDir, "spec.md")
	if err := os.WriteFile(specFile, []byte("# REQ-001"), 0644); err != nil {
		t.Fatal(err)
	}

	// Code references REQ-001 but contains TODO and silent swallow
	codeFile := filepath.Join(tmpDir, "worker.go")
	codeContent := `package main

// REQ-001 implementation
func Process() error {
	// TODO: implement actual logic
	var err error
	if err != nil { return nil }
	return nil
}
`
	if err := os.WriteFile(codeFile, []byte(codeContent), 0644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"--spec", specFile, "--target", tmpDir}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("expected exit 1, got %d", code)
	}

	out := stdout.String()
	if !bytes.Contains([]byte(out), []byte("UNRESOLVED_PLACEHOLDER")) {
		t.Fatalf("expected UNRESOLVED_PLACEHOLDER in stdout, got: %s", out)
	}
	if !bytes.Contains([]byte(out), []byte("SILENT_EXCEPTION_SWALLOW")) {
		t.Fatalf("expected SILENT_EXCEPTION_SWALLOW in stdout, got: %s", out)
	}
}

func TestSpecTraceJsonOutput(t *testing.T) {
	tmpDir := t.TempDir()
	specFile := filepath.Join(tmpDir, "spec.md")
	_ = os.WriteFile(specFile, []byte("# REQ-101\n"), 0644)
	codeFile := filepath.Join(tmpDir, "code.go")
	_ = os.WriteFile(codeFile, []byte("package main\n// REQ-101\n"), 0644)

	var stdout, stderr bytes.Buffer
	code := Run([]string{"--spec", specFile, "--target", tmpDir, "--format", "json"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected exit 0, got %d, stderr: %s", code, stderr.String())
	}

	var res Result
	if err := json.Unmarshal(stdout.Bytes(), &res); err != nil {
		t.Fatalf("failed to unmarshal JSON output: %v", err)
	}
	if !res.Passed || res.Status != "PASS" {
		t.Fatalf("expected PASS result, got %+v", res)
	}
	if len(res.SpecIDs) != 1 || res.SpecIDs[0] != "REQ-101" {
		t.Fatalf("expected REQ-101 in SpecIDs, got %v", res.SpecIDs)
	}
}

func TestSpecTraceInvalidTarget(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := Run([]string{"--target", "/path/that/does/not/exist/999"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("expected exit 2 for invalid target, got %d", code)
	}
}

func TestSpecTraceHelp(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := Run([]string{"--help"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("expected exit 0 for --help, got %d", code)
	}
}
