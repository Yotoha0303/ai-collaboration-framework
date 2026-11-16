# agent-guard

Enterprise-grade quality gates and context lifecycle governance for AI agents.

## Features

- **Pre-action Workspace Verification**: Validates Git repository status, verifies baseline documentation, and intercepts merge conflict markers before agent actions begin.
- **Substantive Assertion Audit**: Scans test files across Python and TypeScript/JavaScript using AST and lexical analysis. Flags empty test bodies, tautological assertions (`assert True`, `expect(true).toBe(true)`), and zero-assertion test suites to prevent silent passes.
- **Context Lifecycle Pruning (Context GC)**: Compresses verbose command output, strips ephemeral progress indicators, and extracts compact Canonical State Assertions.
- **Single Source of Truth (SSOT) State Tracking**: Maintains atomic key-value state to eliminate multi-turn hallucination and state drift.
- **Tombstone Enforcement**: Detects and alerts on references to deprecated technical paths or rejected architectural decisions.

## Installation

```bash
pip install -e packages/agent-guard
```

## Quick Start CLI

### Check Quality Gates

```bash
agent-guard check --path . --stage all
```

Output:
```text
=== agent-guard quality gate scan: /path/to/project ===
[PASS] Stage: PRE-ACTION | Code: PRE_ACTION_GATE_PASSED
       Message: Workspace preconditions satisfied: no merge conflicts and baseline files intact.
[PASS] Stage: TEST-AUDIT | Code: ASSERTION_AUDIT_PASSED
       Message: Audited 10 files with 45 tests and 82 assertions. 0 critical issues found.
--------------------------------------------------
[RESULT] All quality gates PASSED.
```

### Prune Verbose Logs

```bash
agent-guard prune --input test_run.log --tombstones "deprecated_auth,ads_power"
```

Or extract canonical state assertions only:

```bash
agent-guard prune --input test_run.log --extract-assertions
```

### Initialize Project Configuration & Git Hook

```bash
agent-guard init --path .
```
