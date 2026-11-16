"""Command-line interface for agent-guard."""

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from typing import List, Optional

if __package__ is None or __package__ == "":
    import sys
    from pathlib import Path
    _pkg_root = Path(__file__).resolve().parent.parent
    if str(_pkg_root) not in sys.path:
        sys.path.insert(0, str(_pkg_root))
    from agent_guard.context_gc import ContextPruner
    from agent_guard.gates import GateResult, GateStage, QualityGateChecker
else:
    from .context_gc import ContextPruner
    from .gates import GateResult, GateStage, QualityGateChecker


DEFAULT_CONFIG = {
    "version": "1.0",
    "required_baseline_files": ["README.md"],
    "disallow_merge_conflicts": True,
    "test_patterns": [
        "*test*.py",
        "test_*.py",
        "*_test.py",
        "*.test.ts",
        "*.test.js",
        "*.spec.ts",
        "*.spec.js",
    ],
    "strict_mode": False,
    "tombstones": [],
}

PRE_COMMIT_HOOK_TEMPLATE = """#!/usr/bin/env bash
# agent-guard pre-commit hook
# Validates workspace preconditions and intercepts vacuous / silent test passes.
set -euo pipefail

echo "[agent-guard] Running pre-commit quality gates..."
if command -v agent-guard >/dev/null 2>&1; then
    agent-guard check --stage pre-action
else
    python3 -m agent_guard.cli check --stage pre-action
fi
"""


def cmd_check(args: argparse.Namespace) -> int:
    """Execute the check command."""
    target_path = Path(args.path).resolve()
    if not target_path.exists():
        print(f"Error: Target path '{target_path}' does not exist.", file=sys.stderr)
        return 1

    checker = QualityGateChecker(workspace_root=target_path)
    results: List[GateResult] = []

    stage = args.stage
    if stage == "pre-action":
        results.append(checker.check_pre_action_gate())
    elif stage == "test-audit":
        results.append(checker.check_test_audit_gate())
    else:  # 'all'
        results.extend(checker.check_all())

    all_passed = True
    for res in results:
        if not res.passed:
            all_passed = False

    if args.json:
        payload = {
            "all_passed": all_passed,
            "target_path": str(target_path),
            "results": [r.to_dict() for r in results],
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0 if all_passed else 1

    # Human readable output
    print(f"=== agent-guard quality gate scan: {target_path} ===")
    for res in results:
        status_tag = "[PASS]" if res.passed else "[FAIL]"
        print(f"{status_tag} Stage: {res.stage.value.upper()} | Code: {res.code}")
        print(f"       Message: {res.message}")
        if res.details:
            if "conflicted_files" in res.details and res.details["conflicted_files"]:
                print(f"       Conflicted files: {res.details['conflicted_files']}")
            if "findings" in res.details and res.details["findings"]:
                print(f"       Total issues detected: {len(res.details['findings'])}")
                for finding in res.details["findings"][:5]:
                    print(
                        f"         - {finding['file_path']}:{finding['line_number']} "
                        f"[{finding['issue_type']}] in {finding['test_name']}: {finding['description']}"
                    )
                if len(res.details["findings"]) > 5:
                    print(f"         ... and {len(res.details['findings']) - 5} more issues.")

    print("--------------------------------------------------")
    if all_passed:
        print("[RESULT] All quality gates PASSED.")
        return 0
    else:
        print("[RESULT] Quality gate check FAILED.", file=sys.stderr)
        return 1


def cmd_prune(args: argparse.Namespace) -> int:
    """Execute the prune command."""
    input_text = ""
    if args.input == "-" or not args.input:
        if sys.stdin.isatty() and not args.input:
            print("Error: No input provided. Supply a file with --input or pipe text to stdin.", file=sys.stderr)
            return 1
        input_text = sys.stdin.read()
    else:
        input_p = Path(args.input)
        if not input_p.is_file():
            print(f"Error: Input file '{args.input}' does not exist.", file=sys.stderr)
            return 1
        input_text = input_p.read_text(encoding="utf-8")

    tombstones = [t.strip() for t in args.tombstones.split(",")] if args.tombstones else []
    pruner = ContextPruner(tombstones=tombstones)

    if args.extract_assertions:
        assertions = pruner.extract_canonical_assertions(input_text)
        output_content = "\n".join(a.to_line() for a in assertions)
    else:
        output_content = pruner.prune_text(input_text, max_lines=args.max_lines)

    if args.output:
        out_p = Path(args.output)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(output_content, encoding="utf-8")
    else:
        sys.stdout.write(output_content + "\n")

    return 0


def cmd_init(args: argparse.Namespace) -> int:
    """Execute the init command."""
    target_path = Path(args.path).resolve()
    target_path.mkdir(parents=True, exist_ok=True)

    config_path = target_path / ".agent-guard.json"
    if config_path.exists() and not args.force:
        print(f"Configuration file already exists at {config_path}. Use --force to overwrite.")
    else:
        config_path.write_text(json.dumps(DEFAULT_CONFIG, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Generated configuration at {config_path}")

    # Hook template
    template_path = target_path / ".agent-guard-pre-commit.sh"
    if template_path.exists() and not args.force:
        print(f"Hook template already exists at {template_path}. Use --force to overwrite.")
    else:
        template_path.write_text(PRE_COMMIT_HOOK_TEMPLATE, encoding="utf-8")
        # chmod +x
        current_perms = template_path.stat().st_mode
        template_path.chmod(current_perms | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        print(f"Generated pre-commit hook template at {template_path}")

    # Optional: directly install into .git/hooks/pre-commit
    git_hooks_dir = target_path / ".git" / "hooks"
    if args.install_hook or (git_hooks_dir.is_dir() and not (git_hooks_dir / "pre-commit").exists()):
        if git_hooks_dir.is_dir():
            hook_dest = git_hooks_dir / "pre-commit"
            hook_dest.write_text(PRE_COMMIT_HOOK_TEMPLATE, encoding="utf-8")
            hook_dest.chmod(hook_dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            print(f"Installed git pre-commit hook at {hook_dest}")

    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="agent-guard",
        description="Enterprise AI Agent Quality Gates & Context Lifecycle Governance",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # Command: check
    check_p = subparsers.add_parser("check", help="Scan workspace for gate health and assertion validity")
    check_p.add_argument("-p", "--path", default=".", help="Target directory to audit (default: .)")
    check_p.add_argument(
        "-s",
        "--stage",
        choices=["pre-action", "test-audit", "all"],
        default="all",
        help="Gate stage to execute (default: all)",
    )
    check_p.add_argument("--strict", action="store_true", help="Treat missing assertions and warnings as hard errors")
    check_p.add_argument("--json", action="store_true", help="Output machine-readable JSON format")

    # Command: prune
    prune_p = subparsers.add_parser("prune", help="Prune noisy logs and distill canonical state assertions")
    prune_p.add_argument("-i", "--input", default="-", help="Input log file path or '-' for stdin (default: -)")
    prune_p.add_argument("-o", "--output", default=None, help="Output file path (default: stdout)")
    prune_p.add_argument("-t", "--tombstones", default="", help="Comma-separated forbidden tombstone keywords")
    prune_p.add_argument("--max-lines", type=int, default=50, help="Maximum retained lines for body output")
    prune_p.add_argument(
        "--extract-assertions",
        action="store_true",
        help="Only output distilled canonical state assertion lines",
    )

    # Command: init
    init_p = subparsers.add_parser("init", help="Initialize .agent-guard.json and git hook template")
    init_p.add_argument("-p", "--path", default=".", help="Target project root directory (default: .)")
    init_p.add_argument("-f", "--force", action="store_true", help="Overwrite existing configuration and hooks")
    init_p.add_argument("--install-hook", action="store_true", help="Install directly to .git/hooks/pre-commit")

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """Main CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 0

    if args.command == "check":
        return cmd_check(args)
    elif args.command == "prune":
        return cmd_prune(args)
    elif args.command == "init":
        return cmd_init(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
