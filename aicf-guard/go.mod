// ADR-001 §2.4: Go module for the aicf-guard single binary that consolidates
// the five PowerShell guards. ZERO external dependencies — standard library
// only. The module path is the bare binary name (self-hosted framework repo;
// no URL-style path required). If this is ever published, `go mod edit -module`
// can rename it without touching import paths inside the module.
module aicf-guard

// R13 (ADR §2.4): minimum Go version. Set to 1.21 (Go official support
// lower-bound vicinity;主流发行版覆盖). All APIs used are ≤1.21:
//   strings.Cut (1.18) · testing.T.Setenv (1.17) · os.ReadFile (1.16) ·
//   os.ProcessState.ExitCode (1.12) · regexp/exec/path/filepath/bytes (1.0).
// Verified by API inspection against the Go release notes; the local toolchain
// is go1.27.3 (builds a `go 1.21` module cleanly).
go 1.21
