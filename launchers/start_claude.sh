#!/bin/sh
# Launcher for Linux / macOS -- counterpart of start_claude.bat.
#
# The `cd` is the whole point, same as in the .bat: Claude Code finds
# AGENTS.md / .claude/agents/ / settings.json by scanning the start directory
# and its ancestors ONLY, never downward. Launch from anywhere else and the
# framework silently does not exist (AGENTS.md section 0.0).
#
# `dirname "$0"` so the checkout can live anywhere; the visible error is
# deliberate -- a silent wrong-directory launch is the failure mode this
# guards against.
cd "$(dirname "$0")/.." || { echo "start_claude.sh: cannot cd to the workspace root" >&2; exit 1; }
exec claude --dangerously-skip-permissions
