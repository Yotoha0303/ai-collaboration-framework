"""Context lifecycle pruner and garbage collector for AI agents.

Features:
1. Filters redundant raw execution logs and progress spam.
2. Extracts compact, indisputable Canonical State Assertions.
3. Manages Single Source of Truth (SSOT) state tracking and atomic overwrites.
4. Registers and enforces Tombstone markers to prevent resurrection of deprecated paths.
"""

import json
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Pattern, Set, Tuple


@dataclass
class CanonicalStateAssertion:
    """A compact, factual state assertion distilled from raw execution outputs."""
    key: str
    value: Any
    scope: str = "execution"
    confidence: float = 1.0
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_line(self) -> str:
        val_str = json.dumps(self.value) if isinstance(self.value, (dict, list, bool)) else str(self.value)
        return f"[STATE_ASSERTION:{self.scope}] {self.key}={val_str}"


class TombstoneRegistry:
    """Maintains tombstoned (deprecated / rejected) architecture paths and technical choices."""

    def __init__(self, initial_tombstones: Optional[List[str]] = None):
        self._tombstones: Set[str] = set()
        if initial_tombstones:
            for item in initial_tombstones:
                self.add_tombstone(item)

    def add_tombstone(self, pattern: str) -> None:
        """Add a forbidden keyword, path, or pattern to the tombstone registry."""
        cleaned = pattern.strip().lower()
        if cleaned:
            self._tombstones.add(cleaned)

    def remove_tombstone(self, pattern: str) -> None:
        """Remove a tombstone if a path is resurrected under authorized circumstances."""
        cleaned = pattern.strip().lower()
        self._tombstones.discard(cleaned)

    def get_tombstones(self) -> List[str]:
        """Return all active tombstones."""
        return sorted(list(self._tombstones))

    def check(self, content: str) -> List[str]:
        """Check content against tombstone registry and return all matched tombstones."""
        lower_content = content.lower()
        violations = []
        for tombstone in self._tombstones:
            if re.search(r'\b' + re.escape(tombstone) + r'\b', lower_content):
                violations.append(tombstone)
            elif tombstone in lower_content:
                violations.append(tombstone)
        return sorted(list(set(violations)))


class SSOTState:
    """Single Source of Truth state store to prevent long-context memory drift."""

    def __init__(self, initial_state: Optional[Dict[str, Any]] = None):
        self._state: Dict[str, Any] = {}
        self._history: Dict[str, List[Dict[str, Any]]] = {}
        if initial_state:
            for k, v in initial_state.items():
                self.set(k, v, source="init")

    def get(self, key: str, default: Any = None) -> Any:
        return self._state.get(key, default)

    def set(self, key: str, value: Any, source: str = "direct") -> None:
        """Atomically set/overwrite a key in the SSOT state store."""
        ts = datetime.now(timezone.utc).isoformat()
        prev = self._state.get(key)
        self._state[key] = value

        if key not in self._history:
            self._history[key] = []
        self._history[key].append({
            "timestamp": ts,
            "old_value": prev,
            "new_value": value,
            "source": source
        })

    def snapshot(self) -> Dict[str, Any]:
        """Return a copy of the current state snapshot."""
        return dict(self._state)

    def export_canonical_assertions(self) -> List[CanonicalStateAssertion]:
        """Export current state as a list of canonical state assertions."""
        assertions = []
        for k, v in sorted(self._state.items()):
            assertions.append(CanonicalStateAssertion(
                key=k,
                value=v,
                scope="ssot"
            ))
        return assertions


class ContextPruner:
    """Prunes noisy text/logs and extracts concise state assertions."""

    # Patterns for disposable progress/loading bars and noisy spinners
    PROGRESS_PATTERNS: List[Pattern] = [
        re.compile(r'(\[=+>?\s*\]|\r\s*|\b\d+%\s*(?:completed|done|progress)?|\.{3,})', re.IGNORECASE),
        re.compile(r'npm\s+warn\b.*', re.IGNORECASE),
        re.compile(r'^\s*[\│\┃\║\:\.\#\-\*\=]{10,}\s*$', re.MULTILINE),
    ]

    # Extraction patterns for test frameworks
    UNITTEST_OK_RE = re.compile(r'Ran\s+(\d+)\s+tests?\s+in\s+([0-9\.]+)s\s*\n\s*(OK(?:\s*\(.*?\))?)', re.MULTILINE)
    UNITTEST_FAIL_RE = re.compile(r'FAILED\s*\((?:failures=(\d+))?(?:,\s*)?(?:errors=(\d+))?\)', re.MULTILINE)
    PYTEST_RE = re.compile(r'=+\s*(?:(\d+)\s+passed)?(?:,\s*(\d+)\s+failed)?.*?in\s+([0-9\.]+)s\s*=+', re.MULTILINE | re.IGNORECASE)
    VITEST_RE = re.compile(r'Tests\s+(\d+)\s+passed\s*(?:\((\d+)\))?', re.MULTILINE | re.IGNORECASE)
    COMMAND_EXIT_RE = re.compile(r'Command exited with code\s+(\d+)', re.MULTILINE)
    GIT_HEAD_RE = re.compile(r'\b([0-9a-f]{7,40})\b')

    def __init__(self, tombstones: Optional[List[str]] = None):
        self.tombstone_registry = TombstoneRegistry(tombstones)
        self.ssot = SSOTState()

    def extract_canonical_assertions(self, text: str) -> List[CanonicalStateAssertion]:
        """Extract canonical state assertions from raw execution logs."""
        assertions: List[CanonicalStateAssertion] = []

        # 1. Command exit code
        exit_match = self.COMMAND_EXIT_RE.search(text)
        if exit_match:
            code = int(exit_match.group(1))
            assertions.append(CanonicalStateAssertion(
                key="command_exit_code",
                value=code,
                scope="process"
            ))
            self.ssot.set("last_exit_code", code, source="log_extract")

        # 2. Python unittest
        ut_match = self.UNITTEST_OK_RE.search(text)
        if ut_match:
            count = int(ut_match.group(1))
            duration = float(ut_match.group(2))
            assertions.append(CanonicalStateAssertion(
                key="unittest_status",
                value={"status": "PASSED", "tests": count, "duration_seconds": duration},
                scope="test"
            ))
            self.ssot.set("test_run", {"framework": "unittest", "status": "PASSED", "total": count}, source="log_extract")

        ut_fail_match = self.UNITTEST_FAIL_RE.search(text)
        if ut_fail_match:
            failures = int(ut_fail_match.group(1) or 0)
            errors = int(ut_fail_match.group(2) or 0)
            assertions.append(CanonicalStateAssertion(
                key="unittest_status",
                value={"status": "FAILED", "failures": failures, "errors": errors},
                scope="test"
            ))
            self.ssot.set("test_run", {"framework": "unittest", "status": "FAILED", "failures": failures}, source="log_extract")

        # 3. Pytest
        pt_match = self.PYTEST_RE.search(text)
        if pt_match:
            passed = int(pt_match.group(1) or 0)
            failed = int(pt_match.group(2) or 0)
            duration = float(pt_match.group(3))
            status = "PASSED" if failed == 0 and passed > 0 else "FAILED"
            assertions.append(CanonicalStateAssertion(
                key="pytest_status",
                value={"status": status, "passed": passed, "failed": failed, "duration_seconds": duration},
                scope="test"
            ))
            self.ssot.set("test_run", {"framework": "pytest", "status": status, "passed": passed, "failed": failed}, source="log_extract")

        # 4. Vitest / Jest
        vt_match = self.VITEST_RE.search(text)
        if vt_match:
            passed = int(vt_match.group(1))
            assertions.append(CanonicalStateAssertion(
                key="vitest_status",
                value={"status": "PASSED", "passed": passed},
                scope="test"
            ))
            self.ssot.set("test_run", {"framework": "vitest", "status": "PASSED", "passed": passed}, source="log_extract")

        # 5. Git status clean check
        if "working tree clean" in text:
            assertions.append(CanonicalStateAssertion(
                key="git_working_tree",
                value="clean",
                scope="vcs"
            ))
            self.ssot.set("git_clean", True, source="log_extract")
        elif "Changes to be committed" in text or "Changes not staged for commit" in text:
            assertions.append(CanonicalStateAssertion(
                key="git_working_tree",
                value="dirty",
                scope="vcs"
            ))
            self.ssot.set("git_clean", False, source="log_extract")

        return assertions

    def prune_text(self, text: str, max_lines: int = 50, head_lines: int = 15, tail_lines: int = 25) -> str:
        """Prunes long text, compressing verbose repetition and highlighting state assertions."""
        if not text:
            return ""

        lines = text.splitlines()

        # Step 1: Remove trivial blank lines and progress noise
        filtered_lines = []
        for line in lines:
            # Check if line matches ephemeral progress noise
            stripped = line.strip()
            if not stripped:
                filtered_lines.append("")
                continue

            is_noise = False
            for p in self.PROGRESS_PATTERNS:
                if p.match(stripped):
                    is_noise = True
                    break

            if not is_noise:
                filtered_lines.append(line)

        # Step 2: Extract canonical assertions
        assertions = self.extract_canonical_assertions(text)
        assertion_block = [a.to_line() for a in assertions]

        # Step 3: Check for tombstones
        violations = self.tombstone_registry.check(text)
        tombstone_warnings = []
        if violations:
            for v in violations:
                tombstone_warnings.append(f"[TOMBSTONE_VIOLATION] Found reference to forbidden/deprecated path: '{v}'")

        # Step 4: Truncate oversized output
        body_lines = filtered_lines
        if len(body_lines) > max_lines:
            omitted = len(body_lines) - head_lines - tail_lines
            if omitted > 0:
                body_lines = (
                    body_lines[:head_lines]
                    + [f"... [Pruned {omitted} lines of verbose raw execution output] ..."]
                    + body_lines[-tail_lines:]
                )

        output_parts = []
        if assertion_block:
            output_parts.append("\n".join(assertion_block))
        if tombstone_warnings:
            output_parts.append("\n".join(tombstone_warnings))
        output_parts.append("\n".join(body_lines))

        return "\n\n".join(output_parts).strip()
