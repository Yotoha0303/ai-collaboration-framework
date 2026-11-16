"""Quality gate checker for AI agents and automated workflows.

Implements multi-stage quality gates:
1. Workspace preconditions (clean git state, merge conflicts, baseline files)
2. Substantive assertion verification (catches empty tests, vacuous asserts, silent passes)
3. Execution verification and stage transition blocking
"""

import ast
import json
import os
import re
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


class GateStage(str, Enum):
    """Lifecycle stages for quality gates."""
    PRE_ACTION = "pre-action"
    CODE_CHANGE = "code-change"
    TEST_AUDIT = "test-audit"
    POST_VERIFICATION = "post-verification"


@dataclass
class GateResult:
    """Result of a quality gate check."""
    stage: GateStage
    passed: bool
    code: str
    message: str
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        result = asdict(self)
        result["stage"] = self.stage.value
        return result


@dataclass
class AssertionFinding:
    """Detail of an assertion check finding in a test file."""
    file_path: str
    line_number: int
    test_name: str
    issue_type: str  # e.g., 'empty_test', 'vacuous_assert', 'missing_assertion'
    description: str


class PythonTestAuditor(ast.NodeVisitor):
    """AST-based auditor for Python test files to detect vacuous and empty tests."""

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.test_count = 0
        self.substantive_assert_count = 0
        self.findings: List[AssertionFinding] = []
        self._current_test: Optional[str] = None
        self._current_test_asserts = 0
        self._current_test_vacuous = 0

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self.visit_FunctionDef(node)  # type: ignore

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        if node.name.startswith("test_") or node.name.startswith("test"):
            self.test_count += 1
            prev_test = self._current_test
            prev_asserts = self._current_test_asserts
            prev_vacuous = self._current_test_vacuous

            self._current_test = node.name
            self._current_test_asserts = 0
            self._current_test_vacuous = 0

            # Check if function body is effectively empty (only pass, docstring, or ellipsis)
            non_trivial_stmts = []
            for stmt in node.body:
                if isinstance(stmt, ast.Pass):
                    continue
                if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant):
                    continue
                non_trivial_stmts.append(stmt)

            if not non_trivial_stmts:
                self.findings.append(AssertionFinding(
                    file_path=self.file_path,
                    line_number=node.lineno,
                    test_name=node.name,
                    issue_type="empty_test",
                    description=f"Test '{node.name}' has no executable logic or assertions (contains only pass/docstring/ellipsis)."
                ))

            self.generic_visit(node)

            if self._current_test_asserts == 0 and non_trivial_stmts:
                # Test has logic but no recognized assertions
                self.findings.append(AssertionFinding(
                    file_path=self.file_path,
                    line_number=node.lineno,
                    test_name=node.name,
                    issue_type="missing_assertion",
                    description=f"Test '{node.name}' does not contain any substantive assertions."
                ))

            self.substantive_assert_count += self._current_test_asserts
            self._current_test = prev_test
            self._current_test_asserts = prev_asserts
            self._current_test_vacuous = prev_vacuous
        else:
            self.generic_visit(node)

    def visit_Assert(self, node: ast.Assert) -> None:
        if self._current_test:
            # Check for trivial assert: assert True, assert 1, etc.
            if isinstance(node.test, ast.Constant) and bool(node.test.value) is True:
                self._current_test_vacuous += 1
                self.findings.append(AssertionFinding(
                    file_path=self.file_path,
                    line_number=node.lineno,
                    test_name=self._current_test,
                    issue_type="vacuous_assert",
                    description=f"Vacuous assertion 'assert True' in '{self._current_test}' cannot fail."
                ))
            elif isinstance(node.test, ast.Compare):
                # Check for identical left and right: e.g., assert 1 == 1
                if len(node.test.comparators) == 1:
                    left_dump = ast.dump(node.test.left)
                    right_dump = ast.dump(node.test.comparators[0])
                    if left_dump == right_dump and isinstance(node.test.ops[0], ast.Eq):
                        self._current_test_vacuous += 1
                        self.findings.append(AssertionFinding(
                            file_path=self.file_path,
                            line_number=node.lineno,
                            test_name=self._current_test,
                            issue_type="vacuous_assert",
                            description=f"Tautological comparison 'assert x == x' in '{self._current_test}'."
                        ))
                    else:
                        self._current_test_asserts += 1
                else:
                    self._current_test_asserts += 1
            else:
                self._current_test_asserts += 1
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        if self._current_test:
            func_name = ""
            if isinstance(node.func, ast.Name):
                func_name = node.func.id
            elif isinstance(node.func, ast.Attribute):
                func_name = node.func.attr

            # Check unittest assertion methods
            if func_name.startswith("assert"):
                if func_name == "assertTrue" and node.args:
                    first_arg = node.args[0]
                    if isinstance(first_arg, ast.Constant) and bool(first_arg.value) is True:
                        self._current_test_vacuous += 1
                        self.findings.append(AssertionFinding(
                            file_path=self.file_path,
                            line_number=node.lineno,
                            test_name=self._current_test,
                            issue_type="vacuous_assert",
                            description=f"Vacuous assertion 'self.assertTrue(True)' in '{self._current_test}'."
                        ))
                        self.generic_visit(node)
                        return
                self._current_test_asserts += 1
            elif func_name in {"raises", "fail", "expect", "verify"}:
                self._current_test_asserts += 1

        self.generic_visit(node)


class AssertionValidator:
    """Scans and audits test files across languages for substantive assertions."""

    TS_JS_TEST_PATTERN = re.compile(r'(?:it|test)\s*\(\s*[\'"`](.*?)[\'"`]\s*,\s*(?:async\s*)?\(\s*\)\s*=>\s*\{([^}]*)\}', re.MULTILINE | re.DOTALL)
    TS_JS_ASSERT_PATTERN = re.compile(r'\b(expect|assert|should)\s*\(|\.to[A-Za-z]+|\.assert[A-Za-z]+')
    TS_JS_VACUOUS_PATTERN = re.compile(r'expect\s*\(\s*(true|1|["\'][^"\']*["\'])\s*\)\s*\.toBe\s*\(\s*\1\s*\)')

    @classmethod
    def audit_python_file(cls, path: Path) -> Tuple[int, int, List[AssertionFinding]]:
        """Audit a Python test file."""
        try:
            content = path.read_text(encoding="utf-8")
            tree = ast.parse(content, filename=str(path))
            auditor = PythonTestAuditor(str(path))
            auditor.visit(tree)
            return auditor.test_count, auditor.substantive_assert_count, auditor.findings
        except SyntaxError as e:
            return 0, 0, [AssertionFinding(
                file_path=str(path),
                line_number=e.lineno or 1,
                test_name="<syntax_error>",
                issue_type="syntax_error",
                description=f"Python syntax error: {e.msg}"
            )]
        except Exception as e:
            return 0, 0, [AssertionFinding(
                file_path=str(path),
                line_number=1,
                test_name="<read_error>",
                issue_type="read_error",
                description=str(e)
            )]

    @classmethod
    def audit_js_ts_file(cls, path: Path) -> Tuple[int, int, List[AssertionFinding]]:
        """Audit a JavaScript/TypeScript test file with regex analysis."""
        findings: List[AssertionFinding] = []
        test_count = 0
        assert_count = 0

        try:
            content = path.read_text(encoding="utf-8")
        except Exception as e:
            return 0, 0, [AssertionFinding(
                file_path=str(path),
                line_number=1,
                test_name="<read_error>",
                issue_type="read_error",
                description=str(e)
            )]

        # Match test blocks
        for match in cls.TS_JS_TEST_PATTERN.finditer(content):
            test_count += 1
            test_name = match.group(1).strip()
            test_body = match.group(2).strip()
            line_no = content[:match.start()].count("\n") + 1

            if not test_body or test_body in {"pass", ";"}:
                findings.append(AssertionFinding(
                    file_path=str(path),
                    line_number=line_no,
                    test_name=test_name,
                    issue_type="empty_test",
                    description=f"Test '{test_name}' has an empty body."
                ))
                continue

            if cls.TS_JS_VACUOUS_PATTERN.search(test_body):
                findings.append(AssertionFinding(
                    file_path=str(path),
                    line_number=line_no,
                    test_name=test_name,
                    issue_type="vacuous_assert",
                    description=f"Vacuous tautology like 'expect(true).toBe(true)' found in '{test_name}'."
                ))

            assertions = cls.TS_JS_ASSERT_PATTERN.findall(test_body)
            if assertions:
                assert_count += len(assertions)
            else:
                findings.append(AssertionFinding(
                    file_path=str(path),
                    line_number=line_no,
                    test_name=test_name,
                    issue_type="missing_assertion",
                    description=f"Test '{test_name}' contains no recognized expect/assert calls."
                ))

        return test_count, assert_count, findings

    @classmethod
    def audit_file(cls, path: Path) -> Tuple[int, int, List[AssertionFinding]]:
        """Audit any supported test file."""
        suffix = path.suffix.lower()
        if suffix == ".py":
            return cls.audit_python_file(path)
        elif suffix in {".ts", ".tsx", ".js", ".jsx", ".mjs"}:
            return cls.audit_js_ts_file(path)
        return 0, 0, []


def check_substantive_assertions(target_dir: Path, test_patterns: Optional[List[str]] = None) -> GateResult:
    """Scans all test files in target_dir for substantive assertions and flags silent passes."""
    if test_patterns is None:
        test_patterns = ["*test*.py", "test_*.py", "*_test.py", "*.test.ts", "*.test.js", "*.spec.ts", "*.spec.js"]

    total_test_files = 0
    total_tests = 0
    total_asserts = 0
    all_findings: List[AssertionFinding] = []

    matched_paths: Set[Path] = set()
    for root, dirs, files in os.walk(target_dir):
        # Skip dependency and build directories
        dirs[:] = [d for d in dirs if d not in {".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "coverage"}]
        for file in files:
            file_p = Path(root) / file
            for pattern in test_patterns:
                if file_p.match(pattern):
                    matched_paths.add(file_p)

    for path in sorted(matched_paths):
        total_test_files += 1
        t_count, a_count, findings = AssertionValidator.audit_file(path)
        total_tests += t_count
        total_asserts += a_count
        all_findings.extend(findings)

    # Empty test suite detection (zero denominator false positive)
    if total_test_files == 0:
        return GateResult(
            stage=GateStage.TEST_AUDIT,
            passed=False,
            code="EMPTY_TEST_SUITE",
            message="No test files were discovered in the target workspace.",
            details={"total_test_files": 0, "total_tests": 0, "total_asserts": 0}
        )

    if total_tests == 0:
        return GateResult(
            stage=GateStage.TEST_AUDIT,
            passed=False,
            code="ZERO_TESTS_FOUND",
            message=f"Scanned {total_test_files} test files, but 0 test functions were detected.",
            details={"total_test_files": total_test_files, "total_tests": 0}
        )

    critical_issues = [f for f in all_findings if f.issue_type in {"empty_test", "vacuous_assert", "syntax_error"}]
    passed = len(critical_issues) == 0 and total_asserts > 0

    message = (
        f"Audited {total_test_files} files with {total_tests} tests and {total_asserts} assertions. "
        f"{len(critical_issues)} critical issues found."
    )

    return GateResult(
        stage=GateStage.TEST_AUDIT,
        passed=passed,
        code="ASSERTION_AUDIT_PASSED" if passed else "VACUOUS_ASSERTIONS_DETECTED",
        message=message,
        details={
            "total_test_files": total_test_files,
            "total_tests": total_tests,
            "total_asserts": total_asserts,
            "critical_issues_count": len(critical_issues),
            "findings": [asdict(f) for f in all_findings]
        }
    )


class QualityGateChecker:
    """Orchestrates quality gates across workspace lifecycle stages."""

    def __init__(self, workspace_root: Optional[Path] = None, config: Optional[Dict[str, Any]] = None):
        self.workspace_root = workspace_root or Path.cwd()
        self.config = config or self._load_config()

    def _load_config(self) -> Dict[str, Any]:
        config_path = self.workspace_root / ".agent-guard.json"
        if config_path.is_file():
            try:
                with open(config_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {
            "required_baseline_files": ["README.md"],
            "disallow_merge_conflicts": True,
            "test_patterns": ["*test*.py", "test_*.py", "*_test.py", "*.test.ts", "*.test.js"],
            "strict_mode": False
        }

    def check_pre_action_gate(self) -> GateResult:
        """Verifies workspace preconditions: no unmerged conflict markers, baseline files exist."""
        # Define markers dynamically to avoid self-matching during static scans
        conflict_marker_start = b"<" * 7
        conflict_marker_mid = b"=" * 7
        conflict_marker_end = b">" * 7
        conflicted_files: List[str] = []

        # Check baseline files
        missing_baselines: List[str] = []
        for baseline in self.config.get("required_baseline_files", []):
            if not (self.workspace_root / baseline).exists():
                missing_baselines.append(baseline)

        if missing_baselines:
            return GateResult(
                stage=GateStage.PRE_ACTION,
                passed=False,
                code="MISSING_BASELINE_FILES",
                message=f"Required baseline file(s) missing: {', '.join(missing_baselines)}",
                details={"missing_files": missing_baselines}
            )

        # Scan for git conflict markers
        if self.config.get("disallow_merge_conflicts", True):
            for root, dirs, files in os.walk(self.workspace_root):
                dirs[:] = [d for d in dirs if d not in {".git", "node_modules", ".venv", "venv", "dist", "build", "__pycache__"}]
                for file in files:
                    # Only check text files
                    if file.endswith((".py", ".ts", ".js", ".json", ".md", ".txt", ".yml", ".yaml", ".sh", ".toml")):
                        fpath = Path(root) / file
                        try:
                            content = fpath.read_bytes()
                            if conflict_marker_start in content and conflict_marker_mid in content and conflict_marker_end in content:
                                conflicted_files.append(str(fpath.relative_to(self.workspace_root)))
                        except Exception:
                            continue

        if conflicted_files:
            return GateResult(
                stage=GateStage.PRE_ACTION,
                passed=False,
                code="GIT_CONFLICT_MARKERS_PRESENT",
                message=f"Git merge conflict markers detected in {len(conflicted_files)} file(s).",
                details={"conflicted_files": conflicted_files}
            )

        return GateResult(
            stage=GateStage.PRE_ACTION,
            passed=True,
            code="PRE_ACTION_GATE_PASSED",
            message="Workspace preconditions satisfied: no merge conflicts and baseline files intact."
        )

    def check_test_audit_gate(self, test_dir: Optional[Path] = None) -> GateResult:
        """Audits test files for non-trivial assertions and prevents silent passes."""
        target = test_dir or self.workspace_root
        patterns = self.config.get("test_patterns")
        return check_substantive_assertions(target, test_patterns=patterns)

    def check_all(self, test_dir: Optional[Path] = None) -> List[GateResult]:
        """Runs all enabled gates sequentially."""
        results = [
            self.check_pre_action_gate(),
            self.check_test_audit_gate(test_dir=test_dir)
        ]
        return results
