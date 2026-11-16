"""Comprehensive test suite for agent_guard.

Tests coverage:
1. Multi-stage quality gates (workspace preconditions, AST assertion auditing, zero-denominator detection).
2. Context GC (log noise reduction, Canonical State Assertion distillation, SSOT state overwrites, tombstones).
3. CLI commands (check, prune, init).
"""

import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

# Ensure agent_guard package is importable regardless of current working directory
_pkg_root = Path(__file__).resolve().parents[1]
if str(_pkg_root) not in sys.path:
    sys.path.insert(0, str(_pkg_root))

from agent_guard.cli import main
from agent_guard.context_gc import (
    CanonicalStateAssertion,
    ContextPruner,
    SSOTState,
    TombstoneRegistry,
)
from agent_guard.gates import (
    AssertionFinding,
    AssertionValidator,
    GateResult,
    GateStage,
    QualityGateChecker,
    check_substantive_assertions,
)


class TestAssertionValidator(unittest.TestCase):
    """Test AST and lexical audit for substantive assertions."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.temp_path = Path(self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_python_empty_test_body_flagged(self):
        test_file = self.temp_path / "test_empty.py"
        test_file.write_text(
            "def test_should_do_something():\n"
            "    '''Docstring only'''\n"
            "    pass\n"
        )
        t_count, a_count, findings = AssertionValidator.audit_python_file(test_file)
        self.assertEqual(t_count, 1)
        self.assertEqual(a_count, 0)
        self.assertTrue(any(f.issue_type == "empty_test" for f in findings))

    def test_python_vacuous_assert_true_flagged(self):
        test_file = self.temp_path / "test_vacuous.py"
        test_file.write_text(
            "def test_vacuous():\n"
            "    assert True\n"
        )
        t_count, a_count, findings = AssertionValidator.audit_python_file(test_file)
        self.assertEqual(t_count, 1)
        self.assertTrue(any(f.issue_type == "vacuous_assert" for f in findings))

    def test_python_tautology_comparison_flagged(self):
        test_file = self.temp_path / "test_tautology.py"
        test_file.write_text(
            "def test_tautology():\n"
            "    assert 1 == 1\n"
        )
        t_count, a_count, findings = AssertionValidator.audit_python_file(test_file)
        self.assertEqual(t_count, 1)
        self.assertTrue(any(f.issue_type == "vacuous_assert" for f in findings))

    def test_python_substantive_asserts_pass(self):
        test_file = self.temp_path / "test_real.py"
        test_file.write_text(
            "import unittest\n"
            "class SampleTest(unittest.TestCase):\n"
            "    def test_calculation(self):\n"
            "        result = 2 + 2\n"
            "        self.assertEqual(result, 4)\n"
            "        self.assertGreater(result, 0)\n"
        )
        t_count, a_count, findings = AssertionValidator.audit_python_file(test_file)
        self.assertEqual(t_count, 1)
        self.assertGreaterEqual(a_count, 2)
        critical = [f for f in findings if f.issue_type in {"empty_test", "vacuous_assert"}]
        self.assertEqual(len(critical), 0)

    def test_js_ts_empty_and_vacuous_flagged(self):
        test_file = self.temp_path / "sample.test.ts"
        test_file.write_text(
            "it('empty test', () => {});\n"
            "test('tautology test', () => {\n"
            "    expect(true).toBe(true);\n"
            "});\n"
            "test('valid test', () => {\n"
            "    const val = getVal();\n"
            "    expect(val).toBe(42);\n"
            "});\n"
        )
        t_count, a_count, findings = AssertionValidator.audit_js_ts_file(test_file)
        self.assertEqual(t_count, 3)
        self.assertTrue(any(f.issue_type == "empty_test" for f in findings))
        self.assertTrue(any(f.issue_type == "vacuous_assert" for f in findings))
        self.assertGreaterEqual(a_count, 1)


class TestQualityGateChecker(unittest.TestCase):
    """Test QualityGateChecker across stages."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.temp_path = Path(self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_pre_action_missing_baseline(self):
        # Temp dir has no README.md
        checker = QualityGateChecker(workspace_root=self.temp_path)
        result = checker.check_pre_action_gate()
        self.assertFalse(result.passed)
        self.assertEqual(result.code, "MISSING_BASELINE_FILES")

    def test_pre_action_conflict_markers_detected(self):
        (self.temp_path / "README.md").write_text("# Project\n")
        conflict_file = self.temp_path / "conflicted.py"
        c_start = "<" * 7
        c_mid = "=" * 7
        c_end = ">" * 7
        conflict_file.write_text(
            f"def foo():\n"
            f"{c_start} HEAD\n"
            f"    return 1\n"
            f"{c_mid}\n"
            f"    return 2\n"
            f"{c_end} branch\n"
        )
        checker = QualityGateChecker(workspace_root=self.temp_path)
        result = checker.check_pre_action_gate()
        self.assertFalse(result.passed)
        self.assertEqual(result.code, "GIT_CONFLICT_MARKERS_PRESENT")
        self.assertIn("conflicted.py", result.details["conflicted_files"])

    def test_pre_action_clean_passes(self):
        (self.temp_path / "README.md").write_text("# Clean Workspace\n")
        checker = QualityGateChecker(workspace_root=self.temp_path)
        result = checker.check_pre_action_gate()
        self.assertTrue(result.passed)
        self.assertEqual(result.code, "PRE_ACTION_GATE_PASSED")

    def test_test_audit_empty_denominator_fails(self):
        # No test files created in temp_path
        (self.temp_path / "README.md").write_text("# Clean Workspace\n")
        checker = QualityGateChecker(workspace_root=self.temp_path)
        result = checker.check_test_audit_gate()
        self.assertFalse(result.passed)
        self.assertEqual(result.code, "EMPTY_TEST_SUITE")

    def test_test_audit_passes_with_substantive_tests(self):
        (self.temp_path / "README.md").write_text("# Clean Workspace\n")
        test_file = self.temp_path / "test_math.py"
        test_file.write_text(
            "def test_addition():\n"
            "    assert 2 + 2 == 4\n"
        )
        checker = QualityGateChecker(workspace_root=self.temp_path)
        result = checker.check_test_audit_gate()
        self.assertTrue(result.passed)
        self.assertEqual(result.code, "ASSERTION_AUDIT_PASSED")


class TestContextPruner(unittest.TestCase):
    """Test Context GC, Canonical State Assertions, SSOT, and Tombstones."""

    def test_extract_canonical_assertions(self):
        log_sample = (
            "Building project...\n"
            "Ran 15 tests in 0.045s\n"
            "OK\n"
            "Command exited with code 0\n"
            "nothing to commit, working tree clean\n"
        )
        pruner = ContextPruner()
        assertions = pruner.extract_canonical_assertions(log_sample)
        keys = {a.key for a in assertions}
        self.assertIn("command_exit_code", keys)
        self.assertIn("unittest_status", keys)
        self.assertIn("git_working_tree", keys)
        self.assertEqual(pruner.ssot.get("last_exit_code"), 0)
        self.assertTrue(pruner.ssot.get("git_clean"))

    def test_extract_pytest_and_vitest(self):
        log_pytest = "=== 12 passed, 0 failed in 1.45s ==="
        pruner = ContextPruner()
        assertions = pruner.extract_canonical_assertions(log_pytest)
        self.assertTrue(any(a.key == "pytest_status" for a in assertions))

        log_vitest = "Tests  8 passed (8)"
        assertions2 = pruner.extract_canonical_assertions(log_vitest)
        self.assertTrue(any(a.key == "vitest_status" for a in assertions2))

    def test_prune_progress_noise_and_truncation(self):
        pruner = ContextPruner()
        noisy_log = (
            "Starting job...\n"
            "[===>       ] 25%\n"
            "[========>  ] 75%\n"
            "[==========>] 100%\n"
            + "\n".join([f"Processing item {i}" for i in range(100)])
            + "\nCompleted successfully.\nCommand exited with code 0\n"
        )
        pruned = pruner.prune_text(noisy_log, max_lines=20, head_lines=5, tail_lines=5)
        self.assertIn("[STATE_ASSERTION:process] command_exit_code=0", pruned)
        self.assertIn("Pruned", pruned)
        self.assertNotIn("25%", pruned)

    def test_tombstone_detection(self):
        pruner = ContextPruner(tombstones=["ads_power", "legacy_token_v1"])
        bad_text = "Attempting connection using legacy_token_v1 for testing."
        violations = pruner.tombstone_registry.check(bad_text)
        self.assertEqual(violations, ["legacy_token_v1"])

        pruned = pruner.prune_text(bad_text)
        self.assertIn("[TOMBSTONE_VIOLATION]", pruned)
        self.assertIn("legacy_token_v1", pruned)

    def test_ssot_state_and_assertions_export(self):
        ssot = SSOTState({"git_head": "abc1234", "active_env": "production"})
        self.assertEqual(ssot.get("git_head"), "abc1234")

        # Atomic overwrite
        ssot.set("git_head", "def5678", source="git_rev_parse")
        self.assertEqual(ssot.get("git_head"), "def5678")

        assertions = ssot.export_canonical_assertions()
        keys = [a.key for a in assertions]
        self.assertEqual(keys, ["active_env", "git_head"])


class TestCLI(unittest.TestCase):
    """Test CLI commands execution."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.temp_path = Path(self.temp_dir)

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_cli_init_command(self):
        exit_code = main(["init", "--path", str(self.temp_path)])
        self.assertEqual(exit_code, 0)
        self.assertTrue((self.temp_path / ".agent-guard.json").is_file())
        self.assertTrue((self.temp_path / ".agent-guard-pre-commit.sh").is_file())

    def test_cli_check_success(self):
        # Create baseline and valid test
        (self.temp_path / "README.md").write_text("# Test Repo\n")
        (self.temp_path / "test_app.py").write_text("def test_ok():\n    assert 1 + 1 == 2\n")

        exit_code = main(["check", "--path", str(self.temp_path), "--stage", "all"])
        self.assertEqual(exit_code, 0)

    def test_cli_check_failure_on_vacuous_test(self):
        (self.temp_path / "README.md").write_text("# Test Repo\n")
        (self.temp_path / "test_app.py").write_text("def test_fake():\n    pass\n")

        exit_code = main(["check", "--path", str(self.temp_path), "--stage", "test-audit"])
        self.assertEqual(exit_code, 1)

    def test_cli_check_json_output(self):
        (self.temp_path / "README.md").write_text("# Test Repo\n")
        (self.temp_path / "test_app.py").write_text("def test_ok():\n    assert True is not False\n")

        stdout_trap = io.StringIO()
        old_stdout = sys.stdout
        try:
            sys.stdout = stdout_trap
            exit_code = main(["check", "--path", str(self.temp_path), "--stage", "all", "--json"])
        finally:
            sys.stdout = old_stdout

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout_trap.getvalue())
        self.assertTrue(payload["all_passed"])
        self.assertEqual(len(payload["results"]), 2)

    def test_cli_prune_command(self):
        log_file = self.temp_path / "run.log"
        log_file.write_text("Tests  4 passed\nCommand exited with code 0\n")
        out_file = self.temp_path / "pruned.txt"

        exit_code = main(["prune", "--input", str(log_file), "--output", str(out_file), "--extract-assertions"])
        self.assertEqual(exit_code, 0)
        content = out_file.read_text(encoding="utf-8")
        self.assertIn("command_exit_code=0", content)
        self.assertIn("vitest_status", content)


if __name__ == "__main__":
    unittest.main()
